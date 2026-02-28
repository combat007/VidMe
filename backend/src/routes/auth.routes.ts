import { Router } from 'express';
import { getCaptcha, signup, login, getMe, forgotPassword, resetPassword, changePassword } from '../controllers/auth.controller';
import { authenticate } from '../middleware/auth.middleware';

const router = Router();

router.get('/captcha', getCaptcha);
router.post('/signup', signup);
router.post('/login', login);
router.get('/me', authenticate, (req, res) => getMe(req as any, res));
router.post('/forgot-password', forgotPassword);
router.post('/reset-password', resetPassword);
router.post('/change-password', authenticate, (req, res) => changePassword(req as any, res));

export default router;
