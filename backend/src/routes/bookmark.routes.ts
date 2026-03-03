import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware';
import { toggleBookmark, getBookmarkStatus, getBookmarks } from '../controllers/bookmark.controller';

const router = Router();

router.get('/', authenticate, (req, res) => getBookmarks(req as any, res));
router.post('/:id', authenticate, (req, res) => toggleBookmark(req as any, res));
router.get('/:id', authenticate, (req, res) => getBookmarkStatus(req as any, res));

export default router;
