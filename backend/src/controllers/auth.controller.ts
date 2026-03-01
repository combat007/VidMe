import { Request, Response } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/prisma';
import redis from '../config/redis';
import { sendPasswordResetEmail } from '../services/email.service';
import { AuthRequest } from '../middleware/auth.middleware';

// ─── helpers ──────────────────────────────────────────────────────────────────

function issueToken(userId: string) {
  return jwt.sign({ userId }, process.env.JWT_SECRET!, { expiresIn: '7d' });
}

function userPayload(user: { id: string; email: string; age: number; isAdmin: boolean; createdAt: Date }) {
  return { id: user.id, email: user.email, age: user.age, isAdmin: user.isAdmin, createdAt: user.createdAt };
}

/** Find an existing user by provider ID or email; if not found, stash a
 *  10-minute Redis pending entry so the client can supply age. */
async function findOrInitOAuthUser(
  provider: 'google' | 'github',
  providerId: string,
  email: string,
  name?: string,
): Promise<
  | { kind: 'existing'; user: { id: string; email: string; age: number; isAdmin: boolean; createdAt: Date } }
  | { kind: 'pending'; pendingToken: string; email: string }
> {
  // 1. Try by provider ID
  let user =
    provider === 'google'
      ? await prisma.user.findUnique({ where: { googleId: providerId } })
      : await prisma.user.findUnique({ where: { githubId: providerId } });

  // 2. Try by email (link existing password account)
  if (!user) {
    user = await prisma.user.findUnique({ where: { email } });
    if (user) {
      // Link the provider so future logins are faster
      if (provider === 'google' && !user.googleId) {
        await prisma.user.update({ where: { id: user.id }, data: { googleId: providerId } });
      } else if (provider === 'github' && !user.githubId) {
        await prisma.user.update({ where: { id: user.id }, data: { githubId: providerId } });
      }
    }
  }

  if (user) return { kind: 'existing', user };

  // 3. New user — need age before account can be created
  const pendingToken = uuidv4();
  await redis.setex(
    `oauth:pending:${pendingToken}`,
    600,
    JSON.stringify({ provider, providerId, email, name: name ?? '' }),
  );
  return { kind: 'pending', pendingToken, email };
}

// ─── captcha ──────────────────────────────────────────────────────────────────

export async function getCaptcha(req: Request, res: Response): Promise<void> {
  const a = Math.floor(Math.random() * 10) + 1;
  const b = Math.floor(Math.random() * 10) + 1;
  const id = uuidv4();
  await redis.setex(`captcha:${id}`, 300, String(a + b));
  res.json({ id, question: `${a} + ${b}` });
}

// ─── email/password auth ───────────────────────────────────────────────────────

export async function signup(req: Request, res: Response): Promise<void> {
  const { email, password, age, captchaId, captchaAnswer } = req.body;

  if (!email || !password || age === undefined || !captchaId || captchaAnswer === undefined) {
    res.status(400).json({ error: 'All fields are required' });
    return;
  }

  const stored = await redis.get(`captcha:${captchaId}`);
  if (!stored) { res.status(400).json({ error: 'Captcha expired or invalid' }); return; }
  if (Number(captchaAnswer) !== Number(stored)) {
    await redis.del(`captcha:${captchaId}`);
    res.status(400).json({ error: 'Incorrect captcha answer' });
    return;
  }
  await redis.del(`captcha:${captchaId}`);

  const ageNum = Number(age);
  if (isNaN(ageNum) || ageNum < 13 || ageNum > 120) {
    res.status(400).json({ error: 'Age must be between 13 and 120' });
    return;
  }
  if (password.length < 8) {
    res.status(400).json({ error: 'Password must be at least 8 characters' });
    return;
  }

  try {
    if (await prisma.user.findUnique({ where: { email } })) {
      res.status(409).json({ error: 'Email already in use' });
      return;
    }
    const hashed = await bcrypt.hash(password, 12);
    const user = await prisma.user.create({ data: { email, password: hashed, age: ageNum } });
    res.status(201).json({ token: issueToken(user.id), user: userPayload(user) });
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
    if (!user) { res.status(401).json({ error: 'Invalid credentials' }); return; }

    if (!user.password) {
      res.status(400).json({ error: 'This account uses social sign-in. Please use Google or GitHub to log in.' });
      return;
    }

    if (!(await bcrypt.compare(password, user.password))) {
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }

    res.json({ token: issueToken(user.id), user: userPayload(user) });
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
    if (!user) { res.status(404).json({ error: 'User not found' }); return; }
    res.json(user);
  } catch (err) {
    console.error('GetMe error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// ─── Google OAuth ──────────────────────────────────────────────────────────────

/** POST /api/auth/google  { idToken }
 *  Verifies the Google ID token, then finds or initialises the user. */
export async function googleAuth(req: Request, res: Response): Promise<void> {
  const { idToken } = req.body;
  if (!idToken) { res.status(400).json({ error: 'idToken is required' }); return; }

  try {
    const resp = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`);
    const payload = await resp.json() as Record<string, string>;

    if (!resp.ok || payload.error_description) {
      res.status(401).json({ error: 'Invalid Google token' });
      return;
    }

    const clientId = process.env.GOOGLE_CLIENT_ID;
    if (clientId && payload.aud !== clientId) {
      res.status(401).json({ error: 'Token audience mismatch' });
      return;
    }

    const { email, name, sub: googleId } = payload;
    if (!email) { res.status(400).json({ error: 'Google account has no email' }); return; }

    const result = await findOrInitOAuthUser('google', googleId, email, name);

    if (result.kind === 'pending') {
      res.json({ needsAge: true, pendingToken: result.pendingToken, email: result.email });
      return;
    }

    res.json({ token: issueToken(result.user.id), user: userPayload(result.user) });
  } catch (err) {
    console.error('Google auth error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// ─── GitHub OAuth ──────────────────────────────────────────────────────────────

/** GET /api/auth/github?platform=web|mobile
 *  Redirects the browser to GitHub's authorisation page. */
export async function githubInit(req: Request, res: Response): Promise<void> {
  const platform = (req.query.platform as string) || 'web';
  const state = Buffer.from(JSON.stringify({ platform, nonce: uuidv4() })).toString('base64url');
  const frontendUrl = process.env.FRONTEND_URL || 'http://localhost';
  const callbackUrl = encodeURIComponent(`${frontendUrl}/api/auth/github/callback`);
  res.redirect(
    `https://github.com/login/oauth/authorize?client_id=${process.env.GITHUB_CLIENT_ID}&redirect_uri=${callbackUrl}&scope=user%3Aemail&state=${state}`,
  );
}

/** GET /api/auth/github/callback  (GitHub redirects here after authorisation) */
export async function githubCallback(req: Request, res: Response): Promise<void> {
  const { code, state } = req.query as Record<string, string>;
  const frontendUrl = process.env.FRONTEND_URL || 'http://localhost';

  let platform = 'web';
  try { platform = JSON.parse(Buffer.from(state, 'base64url').toString()).platform ?? 'web'; } catch (_) {}

  const redirect = (params: Record<string, string>) => {
    const qs = new URLSearchParams(params).toString();
    if (platform === 'mobile') {
      return res.redirect(`vidmez://oauth/callback?${qs}`);
    }
    return res.redirect(`${frontendUrl}/oauth-callback.html?${qs}`);
  };

  if (!code) { redirect({ error: 'No authorisation code received' }); return; }

  try {
    // Exchange code → access token
    const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: process.env.GITHUB_CLIENT_ID,
        client_secret: process.env.GITHUB_CLIENT_SECRET,
        code,
      }),
    });
    const { access_token: accessToken } = await tokenRes.json() as Record<string, string>;
    if (!accessToken) { redirect({ error: 'Failed to obtain access token' }); return; }

    // Fetch profile
    const profileRes = await fetch('https://api.github.com/user', {
      headers: { Authorization: `Bearer ${accessToken}`, Accept: 'application/vnd.github+json' },
    });
    const profile = await profileRes.json() as Record<string, unknown>;

    // Fetch verified primary email if not public
    let email = profile.email as string | null;
    if (!email) {
      const emailsRes = await fetch('https://api.github.com/user/emails', {
        headers: { Authorization: `Bearer ${accessToken}`, Accept: 'application/vnd.github+json' },
      });
      const emails = await emailsRes.json() as Array<{ email: string; primary: boolean; verified: boolean }>;
      email = emails.find(e => e.primary && e.verified)?.email ?? emails[0]?.email ?? null;
    }
    if (!email) { redirect({ error: 'GitHub account has no verified email' }); return; }

    const result = await findOrInitOAuthUser(
      'github',
      String(profile.id),
      email,
      (profile.name as string) || (profile.login as string),
    );

    if (result.kind === 'pending') {
      redirect({ pending: result.pendingToken, email: result.email });
      return;
    }

    redirect({ token: issueToken(result.user.id) });
  } catch (err) {
    console.error('GitHub callback error:', err);
    redirect({ error: 'Authentication failed' });
  }
}

// ─── OAuth age completion ──────────────────────────────────────────────────────

/** POST /api/auth/oauth/complete  { pendingToken, age }
 *  Called when a new OAuth user submits their age.
 *  Creates the account and returns a JWT. */
export async function oauthComplete(req: Request, res: Response): Promise<void> {
  const { pendingToken, age } = req.body;
  if (!pendingToken || age === undefined) {
    res.status(400).json({ error: 'pendingToken and age are required' });
    return;
  }
  const ageNum = Number(age);
  if (isNaN(ageNum) || ageNum < 13 || ageNum > 120) {
    res.status(400).json({ error: 'Age must be between 13 and 120' });
    return;
  }

  const raw = await redis.get(`oauth:pending:${pendingToken}`);
  if (!raw) { res.status(400).json({ error: 'Session expired. Please try signing in again.' }); return; }

  const { provider, providerId, email, name } = JSON.parse(raw) as {
    provider: 'google' | 'github'; providerId: string; email: string; name: string;
  };
  await redis.del(`oauth:pending:${pendingToken}`);

  try {
    // Race-safe: user might have been created concurrently
    let user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          name: name || null,
          age: ageNum,
          ...(provider === 'google' ? { googleId: providerId } : { githubId: providerId }),
        },
      });
    } else {
      // Just link the provider
      const update = provider === 'google' && !user.googleId
        ? { googleId: providerId }
        : provider === 'github' && !user.githubId
          ? { githubId: providerId }
          : null;
      if (update) await prisma.user.update({ where: { id: user.id }, data: update });
    }

    res.status(201).json({ token: issueToken(user.id), user: userPayload(user) });
  } catch (err) {
    console.error('OAuth complete error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// ─── password management ───────────────────────────────────────────────────────

export async function forgotPassword(req: Request, res: Response): Promise<void> {
  const { email } = req.body;
  if (!email) { res.status(400).json({ error: 'Email is required' }); return; }

  try {
    const user = await prisma.user.findUnique({ where: { email } });
    if (user && user.password) {
      const otp = String(Math.floor(100000 + Math.random() * 900000));
      await redis.setex(`reset:${email}`, 900, otp);
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
    if (!user) { res.status(404).json({ error: 'User not found' }); return; }

    if (!user.password) {
      res.status(400).json({ error: 'Social sign-in accounts do not have a password to change.' });
      return;
    }

    if (!(await bcrypt.compare(currentPassword, user.password))) {
      res.status(401).json({ error: 'Current password is incorrect' });
      return;
    }

    await prisma.user.update({ where: { id: req.userId }, data: { password: await bcrypt.hash(newPassword, 12) } });
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
    if (!user) { res.status(400).json({ error: 'Invalid or expired reset code' }); return; }

    await prisma.user.update({ where: { email }, data: { password: await bcrypt.hash(newPassword, 12) } });
    await redis.del(`reset:${email}`);
    res.json({ message: 'Password reset successfully. You can now log in.' });
  } catch (err) {
    console.error('Reset password error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}
