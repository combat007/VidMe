import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import prisma from './config/prisma';
import redis from './config/redis';
import authRoutes from './routes/auth.routes';
import videoRoutes from './routes/video.routes';
import likeRoutes from './routes/like.routes';
import commentRoutes from './routes/comment.routes';
import adminRoutes from './routes/admin.routes';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/videos', videoRoutes);
app.use('/api/videos', likeRoutes);
app.use('/api/videos', commentRoutes);
app.use('/api/admin', adminRoutes);

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
