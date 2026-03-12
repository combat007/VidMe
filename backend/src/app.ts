import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import prisma from './config/prisma';
import redis from './config/redis';
import authRoutes from './routes/auth.routes';
import videoRoutes from './routes/video.routes';
import likeRoutes from './routes/like.routes';
import commentRoutes from './routes/comment.routes';
import adminRoutes from './routes/admin.routes';
import bookmarkRoutes from './routes/bookmark.routes';
import youtubeRoutes from './routes/youtube.routes';
import { apiLimiter } from './middleware/rate-limit.middleware';

if (!process.env.JWT_SECRET) {
  console.error('FATAL: JWT_SECRET environment variable is not set');
  process.exit(1);
}

const app = express();
const PORT = process.env.PORT || 3000;

// Accept comma-separated origins e.g. "https://www.vidmez.com,https://vidmez.com"
const ALLOWED_ORIGINS = (process.env.FRONTEND_URL || 'http://localhost')
  .split(',').map(o => o.trim()).filter(Boolean);

// Security headers (CSP disabled — Flutter web uses inline scripts)
app.use(helmet({ contentSecurityPolicy: false }));

// Restrict CORS to the configured frontend origin(s)
app.use(cors({
  origin: ALLOWED_ORIGINS.length === 1 ? ALLOWED_ORIGINS[0] : ALLOWED_ORIGINS,
  credentials: true,
}));

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// Baseline rate limit for all /api/ routes
app.use('/api/', apiLimiter);

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/videos', videoRoutes);
app.use('/api/videos', likeRoutes);
app.use('/api/videos', commentRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/bookmarks', bookmarkRoutes);
app.use('/api/youtube', youtubeRoutes);

// Health check — verifies both Postgres and Redis are reachable
app.get('/health', async (_req, res) => {
  const checks: Record<string, string> = {};
  let healthy = true;

  try {
    await prisma.$queryRaw`SELECT 1`;
    checks.postgres = 'ok';
  } catch {
    checks.postgres = 'error';
    healthy = false;
  }

  try {
    await redis.ping();
    checks.redis = 'ok';
  } catch {
    checks.redis = 'error';
    healthy = false;
  }

  res.status(healthy ? 200 : 503).json({ status: healthy ? 'ok' : 'error', checks });
});

const server = app.listen(PORT, () => {
  console.log(`VidMe backend running on port ${PORT}`);
});

// Graceful shutdown on SIGTERM (Kubernetes sends this before SIGKILL)
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(async () => {
    await prisma.$disconnect();
    await redis.quit();
    process.exit(0);
  });

  // Force exit after 30s if drain takes too long
  setTimeout(() => {
    console.error('Forced shutdown after 30s timeout');
    process.exit(1);
  }, 30_000);
});

export default app;
