import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware';
import { toggleLike, getLikes } from '../controllers/like.controller';

const router = Router();

router.post('/:id/like', authenticate, (req, res) => toggleLike(req as any, res));
router.get('/:id/likes', (req, res, next) => {
  const auth = req.headers.authorization;
  if (auth) {
    return authenticate(req as any, res, () => getLikes(req as any, res));
  }
  return getLikes(req as any, res);
});

export default router;
