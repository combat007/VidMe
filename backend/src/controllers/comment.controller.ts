import { Response } from 'express';
import prisma from '../config/prisma';
import { AuthRequest } from '../middleware/auth.middleware';

export async function getComments(req: AuthRequest, res: Response): Promise<void> {
  const { id: videoId } = req.params;
  const page = Math.max(1, Number(req.query.page) || 1);
  const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));

  try {
    const video = await prisma.video.findUnique({ where: { id: videoId } });
    if (!video || video.status !== 'PUBLISHED') {
      res.status(404).json({ error: 'Video not found' });
      return;
    }

    const [comments, total] = await Promise.all([
      prisma.comment.findMany({
        where: { videoId },
        skip: (page - 1) * limit,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: { user: { select: { id: true, email: true } } },
      }),
      prisma.comment.count({ where: { videoId } }),
    ]);

    res.json({
      comments,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (err) {
    console.error('Get comments error:', err);
    res.status(500).json({ error: 'Failed to get comments' });
  }
}

export async function addComment(req: AuthRequest, res: Response): Promise<void> {
  const { id: videoId } = req.params;
  const { content } = req.body;

  if (!content || typeof content !== 'string' || content.trim().length === 0) {
    res.status(400).json({ error: 'Comment content is required' });
    return;
  }
  if (content.length > 2000) {
    res.status(400).json({ error: 'Comment must be 2000 characters or fewer' });
    return;
  }

  try {
    const video = await prisma.video.findUnique({ where: { id: videoId } });
    if (!video || video.status !== 'PUBLISHED') {
      res.status(404).json({ error: 'Video not found' });
      return;
    }
    if (!video.commentsEnabled) {
      res.status(403).json({ error: 'Comments are disabled for this video' });
      return;
    }

    const comment = await prisma.comment.create({
      data: { userId: req.userId!, videoId, content: content.trim() },
      include: { user: { select: { id: true, email: true } } },
    });

    res.status(201).json(comment);
  } catch (err) {
    console.error('Add comment error:', err);
    res.status(500).json({ error: 'Failed to add comment' });
  }
}

export async function deleteComment(req: AuthRequest, res: Response): Promise<void> {
  const { cid: commentId } = req.params;

  try {
    const comment = await prisma.comment.findUnique({ where: { id: commentId } });
    if (!comment) {
      res.status(404).json({ error: 'Comment not found' });
      return;
    }
    if (comment.userId !== req.userId) {
      res.status(403).json({ error: 'Not authorized to delete this comment' });
      return;
    }

    await prisma.comment.delete({ where: { id: commentId } });
    res.json({ message: 'Comment deleted' });
  } catch (err) {
    console.error('Delete comment error:', err);
    res.status(500).json({ error: 'Failed to delete comment' });
  }
}
