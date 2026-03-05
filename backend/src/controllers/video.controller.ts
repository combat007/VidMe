import { Response } from 'express';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import ffmpeg from 'fluent-ffmpeg';
import prisma from '../config/prisma';
import redis from '../config/redis';
import { uploadToIPFS, unpinFromIPFS } from '../services/ipfs.service';
import { getVideoDuration, validateDuration } from '../services/video.service';
import { AuthRequest } from '../middleware/auth.middleware';
import { PINATA_GATEWAY } from '../config/pinata';

const FINALIZE_TTL = 7200; // 2 hours — job result kept in Redis

function extractThumbnail(
  videoPath: string,
  folder: string,
  filename: string,
  timeSeconds: number,
): Promise<void> {
  return new Promise((resolve, reject) => {
    ffmpeg(videoPath)
      .screenshots({
        timestamps: [timeSeconds],
        filename,
        folder,
        size: '1280x720',
      })
      .on('end', () => resolve())
      .on('error', (err: Error) => reject(err));
  });
}

export async function uploadVideoFile(req: AuthRequest, res: Response): Promise<void> {
  if (!req.file) {
    res.status(400).json({ error: 'No video file provided' });
    return;
  }

  const filePath = req.file.path;

  try {
    // Check duration with ffprobe
    let duration: number;
    try {
      duration = await getVideoDuration(filePath);
    } catch (err) {
      fs.unlinkSync(filePath);
      res.status(422).json({ error: 'Could not read video duration. Ensure the file is a valid video.' });
      return;
    }

    const durationError = validateDuration(duration);
    if (durationError) {
      fs.unlinkSync(filePath);
      res.status(422).json({ error: durationError });
      return;
    }

    // Auto-generate thumbnail
    let thumbnailCid: string | null = null;
    let thumbnailUrl: string | null = null;
    const thumbFolder = os.tmpdir();
    const thumbFilename = `vidme-thumb-${Date.now()}.jpg`;
    const thumbPath = path.join(thumbFolder, thumbFilename);
    try {
      const thumbTime = Math.max(1, Math.round(duration * 0.1));
      await extractThumbnail(filePath, thumbFolder, thumbFilename, thumbTime);
      const thumbUpload = await uploadToIPFS(thumbPath, thumbFilename);
      thumbnailCid = thumbUpload.cid;
      thumbnailUrl = thumbUpload.gatewayUrl;
    } catch (thumbErr) {
      console.error('Thumbnail extraction failed (non-fatal):', thumbErr);
    } finally {
      try { if (fs.existsSync(thumbPath)) fs.unlinkSync(thumbPath); } catch (_) {}
    }

    // Upload to IPFS via Pinata
    const fileName = path.basename(req.file.originalname);
    const { cid, gatewayUrl } = await uploadToIPFS(filePath, fileName);

    // Clean up temp file
    fs.unlinkSync(filePath);

    res.json({ cid, gatewayUrl, duration, thumbnailCid, thumbnailUrl });
  } catch (err) {
    // Clean up temp file on error
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    console.error('Video upload error:', err);
    res.status(500).json({ error: 'Failed to upload video to IPFS' });
  }
}

// ── Chunked upload (bypasses Cloudflare 100 MB limit) ───────────────────────

export async function uploadChunk(req: AuthRequest, res: Response): Promise<void> {
  if (!req.file) {
    res.status(400).json({ error: 'No chunk data provided' });
    return;
  }
  const { uploadId, chunkIndex, totalChunks } = req.body;
  if (!uploadId || chunkIndex === undefined || !totalChunks) {
    fs.unlinkSync(req.file.path);
    res.status(400).json({ error: 'Missing chunk metadata (uploadId, chunkIndex, totalChunks)' });
    return;
  }

  const chunkDir = path.join(os.tmpdir(), 'vidme-chunks', uploadId);
  fs.mkdirSync(chunkDir, { recursive: true });
  const dest = path.join(chunkDir, `chunk_${chunkIndex}`);
  fs.renameSync(req.file.path, dest);

  res.json({ received: true, chunkIndex: Number(chunkIndex), totalChunks: Number(totalChunks) });
}

// Runs in background — updates Redis job status when done
async function runFinalize(jobId: string, uploadId: string, totalChunks: number, filename: string) {
  const chunkDir = path.join(os.tmpdir(), 'vidme-chunks', uploadId);
  const ext = path.extname(filename) || '.mp4';
  const assembledPath = path.join(os.tmpdir(), `vidme-assembled-${uploadId}${ext}`);

  const fail = async (msg: string) => {
    await redis.set(`finalize:${jobId}`, JSON.stringify({ status: 'error', error: msg }), 'EX', FINALIZE_TTL);
    if (fs.existsSync(assembledPath)) try { fs.unlinkSync(assembledPath); } catch (_) {}
    if (fs.existsSync(chunkDir)) fs.rmSync(chunkDir, { recursive: true, force: true });
  };

  try {
    // Stream-assemble chunks
    const writeStream = fs.createWriteStream(assembledPath);
    for (let i = 0; i < totalChunks; i++) {
      const chunkPath = path.join(chunkDir, `chunk_${i}`);
      if (!fs.existsSync(chunkPath)) {
        await fail(`Missing chunk ${i}`);
        return;
      }
      await new Promise<void>((resolve, reject) => {
        const rs = fs.createReadStream(chunkPath);
        rs.on('error', reject);
        rs.on('end', resolve);
        rs.pipe(writeStream, { end: false });
      });
    }
    await new Promise<void>((resolve, reject) => {
      writeStream.end();
      writeStream.on('finish', resolve);
      writeStream.on('error', reject);
    });
    fs.rmSync(chunkDir, { recursive: true, force: true });

    // Validate duration
    let duration: number;
    try {
      duration = await getVideoDuration(assembledPath);
    } catch {
      await fail('Could not read video duration. Ensure the file is a valid video.');
      return;
    }
    const durationError = validateDuration(duration);
    if (durationError) {
      await fail(durationError);
      return;
    }

    // Thumbnail
    let thumbnailCid: string | null = null;
    let thumbnailUrl: string | null = null;
    const thumbFilename = `vidme-thumb-${Date.now()}.jpg`;
    const thumbPath = path.join(os.tmpdir(), thumbFilename);
    try {
      const thumbTime = Math.max(1, Math.round(duration * 0.1));
      await extractThumbnail(assembledPath, os.tmpdir(), thumbFilename, thumbTime);
      const thumbUpload = await uploadToIPFS(thumbPath, thumbFilename);
      thumbnailCid = thumbUpload.cid;
      thumbnailUrl = thumbUpload.gatewayUrl;
    } catch (thumbErr) {
      console.error('Thumbnail extraction failed (non-fatal):', thumbErr);
    } finally {
      try { if (fs.existsSync(thumbPath)) fs.unlinkSync(thumbPath); } catch (_) {}
    }

    // Pin to IPFS
    const { cid, gatewayUrl } = await uploadToIPFS(assembledPath, path.basename(filename));
    fs.unlinkSync(assembledPath);

    await redis.set(
      `finalize:${jobId}`,
      JSON.stringify({ status: 'done', result: { cid, gatewayUrl, duration, thumbnailCid, thumbnailUrl } }),
      'EX', FINALIZE_TTL,
    );
  } catch (err) {
    console.error('Chunked upload finalize error:', err);
    await fail('Failed to assemble and upload video').catch(() => {});
  }
}

// POST /api/videos/finalize-upload — returns immediately with jobId
export async function finalizeChunkedUpload(req: AuthRequest, res: Response): Promise<void> {
  const { uploadId, totalChunks, filename } = req.body;
  if (!uploadId || !totalChunks || !filename) {
    res.status(400).json({ error: 'Missing finalize parameters (uploadId, totalChunks, filename)' });
    return;
  }

  const jobId = uuidv4();
  await redis.set(`finalize:${jobId}`, JSON.stringify({ status: 'processing' }), 'EX', FINALIZE_TTL);

  // Fire-and-forget — Cloudflare 100s timeout won't affect this
  runFinalize(jobId, uploadId, Number(totalChunks), filename).catch(console.error);

  res.json({ jobId });
}

// GET /api/videos/finalize-status/:jobId — poll until status != 'processing'
export async function getFinalizeStatus(req: AuthRequest, res: Response): Promise<void> {
  const { jobId } = req.params;
  const raw = await redis.get(`finalize:${jobId}`);
  if (!raw) {
    res.status(404).json({ error: 'Job not found or expired' });
    return;
  }
  res.json(JSON.parse(raw));
}

export async function createVideo(req: AuthRequest, res: Response): Promise<void> {
  const { title, description, ipfsCid, thumbnailCid, duration, is18Plus, likesEnabled, commentsEnabled } = req.body;

  if (!title || !ipfsCid || duration === undefined) {
    res.status(400).json({ error: 'title, ipfsCid, and duration are required' });
    return;
  }

  try {
    const video = await prisma.video.create({
      data: {
        userId: req.userId!,
        title,
        description: description || null,
        ipfsCid,
        thumbnailCid: thumbnailCid || null,
        duration: Number(duration),
        is18Plus: Boolean(is18Plus),
        likesEnabled: likesEnabled !== false,
        commentsEnabled: commentsEnabled !== false,
        status: 'PUBLISHED',
      },
      include: {
        user: { select: { id: true, email: true } },
      },
    });

    res.status(201).json({
      ...video,
      gatewayUrl: `${PINATA_GATEWAY}/${video.ipfsCid}`,
    });
  } catch (err) {
    console.error('Create video error:', err);
    res.status(500).json({ error: 'Failed to create video' });
  }
}

export async function searchSuggestions(req: AuthRequest, res: Response): Promise<void> {
  const q = ((req.query.q as string) || '').trim();
  if (!q) {
    res.json([]);
    return;
  }

  try {
    const videos = await prisma.video.findMany({
      where: {
        status: 'PUBLISHED',
        blocked: false,
        title: { contains: q, mode: 'insensitive' },
      },
      select: { id: true, title: true },
      take: 6,
      orderBy: { createdAt: 'desc' },
    });
    res.json(videos);
  } catch (err) {
    console.error('Search suggestions error:', err);
    res.status(500).json({ error: 'Failed to fetch suggestions' });
  }
}

export async function listVideos(req: AuthRequest, res: Response): Promise<void> {
  const page = Math.max(1, Number(req.query.page) || 1);
  const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
  const filter18plus = req.query.filter18plus === 'true';
  const search = ((req.query.search as string) || '').trim();

  try {
    // Get current user's age for 18+ filtering
    let userAge: number | null = null;
    if (req.userId) {
      const user = await prisma.user.findUnique({ where: { id: req.userId }, select: { age: true } });
      userAge = user?.age ?? null;
    }

    const where: Record<string, unknown> = { status: 'PUBLISHED', blocked: false };

    // Hide 18+ content if user is not authenticated or underage
    if (filter18plus || userAge === null || userAge < 18) {
      where['is18Plus'] = false;
    }

    // Full-text search on title and description
    if (search) {
      where['OR'] = [
        { title: { contains: search, mode: 'insensitive' } },
        { description: { contains: search, mode: 'insensitive' } },
      ];
    }

    const [videos, total] = await Promise.all([
      prisma.video.findMany({
        where,
        skip: (page - 1) * limit,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: {
          user: { select: { id: true, email: true } },
          _count: { select: { likes: true, comments: true } },
        },
      }),
      prisma.video.count({ where }),
    ]);

    res.json({
      videos: videos.map(v => ({
        ...v,
        gatewayUrl: `${PINATA_GATEWAY}/${v.ipfsCid}`,
        thumbnailUrl: v.thumbnailCid ? `${PINATA_GATEWAY}/${v.thumbnailCid}` : null,
      })),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (err) {
    console.error('List videos error:', err);
    res.status(500).json({ error: 'Failed to list videos' });
  }
}

export async function getVideo(req: AuthRequest, res: Response): Promise<void> {
  const { id } = req.params;

  try {
    // Get current user's age
    let userAge: number | null = null;
    if (req.userId) {
      const user = await prisma.user.findUnique({ where: { id: req.userId }, select: { age: true } });
      userAge = user?.age ?? null;
    }

    const video = await prisma.video.findUnique({
      where: { id },
      include: {
        user: { select: { id: true, email: true } },
        _count: { select: { likes: true, comments: true } },
      },
    });

    if (!video || video.status !== 'PUBLISHED') {
      res.status(404).json({ error: 'Video not found' });
      return;
    }

    if (video.blocked) {
      res.status(403).json({ error: 'This video has been removed by an administrator' });
      return;
    }

    // 18+ gate
    if (video.is18Plus && (userAge === null || userAge < 18)) {
      res.status(403).json({ error: 'This video is restricted to users aged 18 and above' });
      return;
    }

    // Increment view count
    await prisma.video.update({ where: { id }, data: { viewCount: { increment: 1 } } });

    res.json({
      ...video,
      viewCount: video.viewCount + 1,
      gatewayUrl: `${PINATA_GATEWAY}/${video.ipfsCid}`,
      thumbnailUrl: video.thumbnailCid ? `${PINATA_GATEWAY}/${video.thumbnailCid}` : null,
    });
  } catch (err) {
    console.error('Get video error:', err);
    res.status(500).json({ error: 'Failed to get video' });
  }
}

export async function updateVideo(req: AuthRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const { title, description, is18Plus, likesEnabled, commentsEnabled } = req.body;

  try {
    const video = await prisma.video.findUnique({ where: { id } });
    if (!video) {
      res.status(404).json({ error: 'Video not found' });
      return;
    }
    if (video.userId !== req.userId) {
      res.status(403).json({ error: 'Not authorized to update this video' });
      return;
    }

    const updated = await prisma.video.update({
      where: { id },
      data: {
        ...(title !== undefined && { title }),
        ...(description !== undefined && { description }),
        ...(is18Plus !== undefined && { is18Plus: Boolean(is18Plus) }),
        ...(likesEnabled !== undefined && { likesEnabled: Boolean(likesEnabled) }),
        ...(commentsEnabled !== undefined && { commentsEnabled: Boolean(commentsEnabled) }),
      },
      include: { user: { select: { id: true, email: true } } },
    });

    res.json({ ...updated, gatewayUrl: `${PINATA_GATEWAY}/${updated.ipfsCid}` });
  } catch (err) {
    console.error('Update video error:', err);
    res.status(500).json({ error: 'Failed to update video' });
  }
}

export async function uploadThumbnailFile(req: AuthRequest, res: Response): Promise<void> {
  if (!req.file) {
    res.status(400).json({ error: 'No thumbnail file provided' });
    return;
  }

  const filePath = req.file.path;
  try {
    const fileName = `thumb-${Date.now()}${path.extname(req.file.originalname)}`;
    const { cid, gatewayUrl } = await uploadToIPFS(filePath, fileName);
    fs.unlinkSync(filePath);
    res.json({ cid, thumbnailUrl: gatewayUrl });
  } catch (err) {
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    console.error('Thumbnail upload error:', err);
    res.status(500).json({ error: 'Failed to upload thumbnail to IPFS' });
  }
}

export async function deleteVideo(req: AuthRequest, res: Response): Promise<void> {
  const { id } = req.params;

  try {
    const video = await prisma.video.findUnique({ where: { id } });
    if (!video) {
      res.status(404).json({ error: 'Video not found' });
      return;
    }
    if (video.userId !== req.userId) {
      res.status(403).json({ error: 'Not authorized to delete this video' });
      return;
    }

    await prisma.video.delete({ where: { id } });

    // Attempt to unpin from IPFS (non-critical)
    unpinFromIPFS(video.ipfsCid).catch(console.error);
    if (video.thumbnailCid) unpinFromIPFS(video.thumbnailCid).catch(console.error);

    res.json({ message: 'Video deleted successfully' });
  } catch (err) {
    console.error('Delete video error:', err);
    res.status(500).json({ error: 'Failed to delete video' });
  }
}
