import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware';
import { getComments, addComment, deleteComment } from '../controllers/comment.controller';

const router = Router();

router.get('/:id/comments', (req, res) => getComments(req as any, res));
router.post('/:id/comments', authenticate, (req, res) => addComment(req as any, res));
router.delete('/:id/comments/:cid', authenticate, (req, res) => deleteComment(req as any, res));

export default router;
