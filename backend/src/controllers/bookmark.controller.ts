import { Response } from 'express';
import prisma from '../config/prisma';
import { PINATA_GATEWAY } from '../config/pinata';
import { AuthRequest } from '../middleware/auth.middleware';

const VIDEO_SELECT = {
  id: true,
  userId: true,
  title: true,
  description: true,
  ipfsCid: true,
  thumbnailCid: true,
  duration: true,
  is18Plus: true,
  blocked: true,
  likesEnabled: true,
  commentsEnabled: true,
  status: true,
  viewCount: true,
  createdAt: true,
  user: { select: { id: true, email: true } },
  _count: { select: { likes: true, comments: true } },
} as const;

function formatVideo(v: { ipfsCid: string; thumbnailCid: string | null; [key: string]: unknown }) {
  return {
    ...v,
    gatewayUrl: `${PINATA_GATEWAY}/${v.ipfsCid}`,
    thumbnailUrl: v.thumbnailCid ? `${PINATA_GATEWAY}/${v.thumbnailCid}` : null,
  };
}

export async function toggleBookmark(req: AuthRequest, res: Response): Promise<void> {
  const { id: videoId } = req.params;
  const userId = req.userId!;

  try {
    const video = await prisma.video.findUnique({
      where: { id: videoId },
      select: { id: true, status: true, blocked: true },
    });

    if (!video || video.status !== 'PUBLISHED' || video.blocked) {
      res.status(404).json({ error: 'Video not found' });
      return;
    }

    const existing = await prisma.bookmark.findUnique({
      where: { userId_videoId: { userId, videoId } },
    });

    if (existing) {
      await prisma.bookmark.delete({ where: { id: existing.id } });
      res.json({ bookmarked: false });
    } else {
      await prisma.bookmark.create({ data: { userId, videoId } });
      res.json({ bookmarked: true });
    }
  } catch (err) {
    console.error('toggleBookmark error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

export async function getBookmarkStatus(req: AuthRequest, res: Response): Promise<void> {
  const { id: videoId } = req.params;
  const userId = req.userId!;

  try {
    const bookmark = await prisma.bookmark.findUnique({
      where: { userId_videoId: { userId, videoId } },
    });
    res.json({ bookmarked: !!bookmark });
  } catch (err) {
    console.error('getBookmarkStatus error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

export async function getBookmarks(req: AuthRequest, res: Response): Promise<void> {
  const userId = req.userId!;
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const limit = Math.min(50, parseInt(req.query.limit as string) || 20);
  const skip = (page - 1) * limit;

  try {
    const [bookmarks, total] = await Promise.all([
      prisma.bookmark.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
        include: { video: { select: VIDEO_SELECT } },
      }),
      prisma.bookmark.count({ where: { userId } }),
    ]);

    // Filter out removed/blocked videos inline
    const videos = bookmarks
      .filter(b => b.video.status === 'PUBLISHED' && !b.video.blocked)
      .map(b => formatVideo(b.video));

    res.json({
      videos,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
      hasMore: page * limit < total,
    });
  } catch (err) {
    console.error('getBookmarks error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}
