import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware';
import { requireAdmin } from '../middleware/admin.middleware';
import { getStats, adminListVideos, adminDeleteVideo, adminBlockVideo, adminUnblockVideo } from '../controllers/admin.controller';

const router = Router();

// All admin routes require JWT + admin flag
router.use(authenticate, requireAdmin);

router.get('/stats', getStats);
router.get('/videos', adminListVideos);
router.delete('/videos/:id', adminDeleteVideo);
router.patch('/videos/:id/block', adminBlockVideo);
router.patch('/videos/:id/unblock', adminUnblockVideo);

export default router;
