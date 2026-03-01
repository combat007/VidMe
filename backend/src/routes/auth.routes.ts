import { Router } from 'express';
import {
  getCaptcha,
  signup,
  login,
  getMe,
  forgotPassword,
  resetPassword,
  changePassword,
  googleAuth,
  githubInit,
  githubCallback,
  oauthComplete,
} from '../controllers/auth.controller';
import { authenticate } from '../middleware/auth.middleware';

const router = Router();

// Email / password
router.get('/captcha', getCaptcha);
router.post('/signup', signup);
router.post('/login', login);
router.get('/me', authenticate, (req, res) => getMe(req as any, res));
router.post('/forgot-password', forgotPassword);
router.post('/reset-password', resetPassword);
router.post('/change-password', authenticate, (req, res) => changePassword(req as any, res));

// OAuth — Google
router.post('/google', googleAuth);

// OAuth — GitHub (browser redirect flow)
router.get('/github', githubInit);
router.get('/github/callback', githubCallback);

// OAuth — age completion for new social users
router.post('/oauth/complete', oauthComplete);

export default router;
