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
  googleInit,
  googleCallback,
  githubInit,
  githubCallback,
  oauthComplete,
} from '../controllers/auth.controller';
import { authenticate } from '../middleware/auth.middleware';
import { authLimiter, signupLimiter } from '../middleware/rate-limit.middleware';

const router = Router();

// Email / password
router.get('/captcha', getCaptcha);
router.post('/signup', signupLimiter, signup);
router.post('/login', authLimiter, login);
router.get('/me', authenticate, (req, res) => getMe(req as any, res));
router.post('/forgot-password', authLimiter, forgotPassword);
router.post('/reset-password', authLimiter, resetPassword);
router.post('/change-password', authenticate, (req, res) => changePassword(req as any, res));

// OAuth — Google
router.post('/google', googleAuth);          // mobile: ID token verification
router.get('/google', googleInit);           // web: redirect flow
router.get('/google/callback', googleCallback);

// OAuth — GitHub (browser redirect flow)
router.get('/github', githubInit);
router.get('/github/callback', githubCallback);

// OAuth — age completion for new social users
router.post('/oauth/complete', oauthComplete);

export default router;
