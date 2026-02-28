import { Response } from 'express';
import prisma from '../config/prisma';
import { AuthRequest } from '../middleware/auth.middleware';

export async function toggleLike(req: AuthRequest, res: Response): Promise<void> {
  const { id: videoId } = req.params;

  try {
    const video = await prisma.video.findUnique({ where: { id: videoId } });
    if (!video || video.status !== 'PUBLISHED') {
      res.status(404).json({ error: 'Video not found' });
      return;
    }
    if (!video.likesEnabled) {
      res.status(403).json({ error: 'Likes are disabled for this video' });
      return;
    }

    const existing = await prisma.like.findUnique({
      where: { userId_videoId: { userId: req.userId!, videoId } },
    });

    let liked: boolean;
    if (existing) {
      await prisma.like.delete({ where: { id: existing.id } });
      liked = false;
    } else {
      await prisma.like.create({ data: { userId: req.userId!, videoId } });
      liked = true;
    }

    const count = await prisma.like.count({ where: { videoId } });
    res.json({ liked, count });
  } catch (err) {
    console.error('Toggle like error:', err);
    res.status(500).json({ error: 'Failed to toggle like' });
  }
}

export async function getLikes(req: AuthRequest, res: Response): Promise<void> {
  const { id: videoId } = req.params;

  try {
    const video = await prisma.video.findUnique({ where: { id: videoId } });
    if (!video || video.status !== 'PUBLISHED') {
      res.status(404).json({ error: 'Video not found' });
      return;
    }

    const count = await prisma.like.count({ where: { videoId } });

    let liked = false;
    if (req.userId) {
      const existing = await prisma.like.findUnique({
        where: { userId_videoId: { userId: req.userId, videoId } },
      });
      liked = !!existing;
    }

    res.json({ count, liked });
  } catch (err) {
    console.error('Get likes error:', err);
    res.status(500).json({ error: 'Failed to get likes' });
  }
}
