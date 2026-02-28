import { Request, Response } from 'express';
import prisma from '../config/prisma';
import { unpinFromIPFS } from '../services/ipfs.service';
import { PINATA_GATEWAY } from '../config/pinata';

export async function getStats(_req: Request, res: Response): Promise<void> {
  try {
    const [totalUsers, totalVideos, blockedVideos, totalViewsAgg] = await Promise.all([
      prisma.user.count(),
      prisma.video.count({ where: { status: 'PUBLISHED' } }),
      prisma.video.count({ where: { blocked: true } }),
      prisma.video.aggregate({ _sum: { viewCount: true } }),
    ]);

    res.json({
      totalUsers,
      totalVideos,
      blockedVideos,
      totalViews: totalViewsAgg._sum.viewCount ?? 0,
    });
  } catch (err) {
    console.error('Admin stats error:', err);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
}

export async function adminListVideos(req: Request, res: Response): Promise<void> {
  const page = Math.max(1, Number(req.query.page) || 1);
  const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
  const search = (req.query.search as string) || '';

  try {
    const where = search
      ? { title: { contains: search, mode: 'insensitive' as const } }
      : {};

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
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (err) {
    console.error('Admin list videos error:', err);
    res.status(500).json({ error: 'Failed to list videos' });
  }
}

export async function adminDeleteVideo(req: Request, res: Response): Promise<void> {
  const { id } = req.params;
  try {
    const video = await prisma.video.findUnique({ where: { id } });
    if (!video) {
      res.status(404).json({ error: 'Video not found' });
      return;
    }

    await prisma.video.delete({ where: { id } });

    unpinFromIPFS(video.ipfsCid).catch(console.error);
    if (video.thumbnailCid) unpinFromIPFS(video.thumbnailCid).catch(console.error);

    res.json({ message: 'Video deleted by admin' });
  } catch (err) {
    console.error('Admin delete video error:', err);
    res.status(500).json({ error: 'Failed to delete video' });
  }
}

export async function adminBlockVideo(req: Request, res: Response): Promise<void> {
  const { id } = req.params;
  try {
    const video = await prisma.video.findUnique({ where: { id } });
    if (!video) {
      res.status(404).json({ error: 'Video not found' });
      return;
    }
    const updated = await prisma.video.update({ where: { id }, data: { blocked: true } });
    res.json({ id: updated.id, blocked: updated.blocked });
  } catch (err) {
    console.error('Admin block video error:', err);
    res.status(500).json({ error: 'Failed to block video' });
  }
}

export async function adminUnblockVideo(req: Request, res: Response): Promise<void> {
  const { id } = req.params;
  try {
    const video = await prisma.video.findUnique({ where: { id } });
    if (!video) {
      res.status(404).json({ error: 'Video not found' });
      return;
    }
    const updated = await prisma.video.update({ where: { id }, data: { blocked: false } });
    res.json({ id: updated.id, blocked: updated.blocked });
  } catch (err) {
    console.error('Admin unblock video error:', err);
    res.status(500).json({ error: 'Failed to unblock video' });
  }
}
