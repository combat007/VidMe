import { Request, Response } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/prisma';
import redis from '../config/redis';
import { sendPasswordResetEmail } from '../services/email.service';
import { AuthRequest } from '../middleware/auth.middleware';

export async function getCaptcha(req: Request, res: Response): Promise<void> {
  const a = Math.floor(Math.random() * 10) + 1;
  const b = Math.floor(Math.random() * 10) + 1;
  const answer = a + b;
  const id = uuidv4();
  await redis.setex(`captcha:${id}`, 300, String(answer));
  res.json({ id, question: `${a} + ${b}` });
}

export async function signup(req: Request, res: Response): Promise<void> {
  const { email, password, age, captchaId, captchaAnswer } = req.body;

  if (!email || !password || age === undefined || !captchaId || captchaAnswer === undefined) {
    res.status(400).json({ error: 'All fields are required' });
    return;
  }

  // Validate captcha
  const stored = await redis.get(`captcha:${captchaId}`);
  if (stored === null) {
    res.status(400).json({ error: 'Captcha expired or invalid' });
    return;
  }
  if (Number(captchaAnswer) !== Number(stored)) {
    await redis.del(`captcha:${captchaId}`);
    res.status(400).json({ error: 'Incorrect captcha answer' });
    return;
  }
  await redis.del(`captcha:${captchaId}`);

  // Validate age
  const ageNum = Number(age);
  if (isNaN(ageNum) || ageNum < 13 || ageNum > 120) {
    res.status(400).json({ error: 'Age must be between 13 and 120' });
    return;
  }

  // Validate password
  if (password.length < 8) {
    res.status(400).json({ error: 'Password must be at least 8 characters' });
    return;
  }

  try {
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) {
      res.status(409).json({ error: 'Email already in use' });
      return;
    }

    const hashed = await bcrypt.hash(password, 12);
    const user = await prisma.user.create({
      data: { email, password: hashed, age: ageNum },
    });

    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET!, { expiresIn: '7d' });
    res.status(201).json({
      token,
      user: { id: user.id, email: user.email, age: user.age, createdAt: user.createdAt },
    });
  } catch (err) {
    console.error('Signup error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

export async function login(req: Request, res: Response): Promise<void> {
  const { email, password } = req.body;

  if (!email || !password) {
    res.status(400).json({ error: 'Email and password are required' });
    return;
  }

  try {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) {
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }

    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET!, { expiresIn: '7d' });
    res.json({
      token,
      user: { id: user.id, email: user.email, age: user.age, createdAt: user.createdAt },
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

export async function getMe(req: AuthRequest, res: Response): Promise<void> {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.userId },
      select: { id: true, email: true, age: true, isAdmin: true, createdAt: true },
    });
    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }
    res.json(user);
  } catch (err) {
    console.error('GetMe error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

export async function forgotPassword(req: Request, res: Response): Promise<void> {
  const { email } = req.body;
  if (!email) {
    res.status(400).json({ error: 'Email is required' });
    return;
  }

  try {
    // Always return success to avoid leaking whether an email is registered
    const user = await prisma.user.findUnique({ where: { email } });
    if (user) {
      const otp = String(Math.floor(100000 + Math.random() * 900000)); // 6-digit code
      await redis.setex(`reset:${email}`, 900, otp); // 15 min TTL
      await sendPasswordResetEmail(email, otp);
    }
    res.json({ message: 'If that email is registered, a reset code has been sent.' });
  } catch (err) {
    console.error('Forgot password error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

export async function changePassword(req: AuthRequest, res: Response): Promise<void> {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) {
    res.status(400).json({ error: 'currentPassword and newPassword are required' });
    return;
  }
  if (newPassword.length < 8) {
    res.status(400).json({ error: 'New password must be at least 8 characters' });
    return;
  }

  try {
    const user = await prisma.user.findUnique({ where: { id: req.userId } });
    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const valid = await bcrypt.compare(currentPassword, user.password);
    if (!valid) {
      res.status(401).json({ error: 'Current password is incorrect' });
      return;
    }

    const hashed = await bcrypt.hash(newPassword, 12);
    await prisma.user.update({ where: { id: req.userId }, data: { password: hashed } });

    res.json({ message: 'Password changed successfully.' });
  } catch (err) {
    console.error('Change password error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

export async function resetPassword(req: Request, res: Response): Promise<void> {
  const { email, otp, newPassword } = req.body;
  if (!email || !otp || !newPassword) {
    res.status(400).json({ error: 'email, otp, and newPassword are required' });
    return;
  }
  if (newPassword.length < 8) {
    res.status(400).json({ error: 'Password must be at least 8 characters' });
    return;
  }

  try {
    const stored = await redis.get(`reset:${email}`);
    if (!stored || stored !== String(otp)) {
      res.status(400).json({ error: 'Invalid or expired reset code' });
      return;
    }

    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      res.status(400).json({ error: 'Invalid or expired reset code' });
      return;
    }

    const hashed = await bcrypt.hash(newPassword, 12);
    await prisma.user.update({ where: { email }, data: { password: hashed } });
    await redis.del(`reset:${email}`);

    res.json({ message: 'Password reset successfully. You can now log in.' });
  } catch (err) {
    console.error('Reset password error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}
