import { Request, Response } from 'express';
import redis from '../config/redis';

const CACHE_TTL = 1800; // 30 minutes

interface YouTubeItem {
  id: string;
  snippet: {
    title: string;
    channelTitle: string;
    channelId: string;
    publishedAt: string;
    thumbnails: {
      maxres?: { url: string };
      high?: { url: string };
      medium?: { url: string };
      default?: { url: string };
    };
  };
  statistics?: {
    viewCount?: string;
    likeCount?: string;
  };
  contentDetails?: {
    duration?: string;
  };
}

export const getTrending = async (req: Request, res: Response) => {
  try {
    const apiKey = process.env.YOUTUBE_API_KEY;
    if (!apiKey) {
      return res.status(503).json({ error: 'YouTube API not configured' });
    }

    const rawRegion = (req.query.regionCode as string) || 'US';
    const regionCode = rawRegion.toUpperCase().slice(0, 2);
    const maxResults = Math.min(parseInt(req.query.maxResults as string) || 20, 50);
    const categoryId = (req.query.categoryId as string) || '';

    const cacheKey = `youtube:trending:${regionCode}:${maxResults}:${categoryId}`;

    // Serve from Redis cache if available
    const cached = await redis.get(cacheKey);
    if (cached) {
      return res.json(JSON.parse(cached));
    }

    // Fetch from YouTube Data API v3
    const url = new URL('https://www.googleapis.com/youtube/v3/videos');
    url.searchParams.set('part', 'snippet,statistics,contentDetails');
    url.searchParams.set('chart', 'mostPopular');
    url.searchParams.set('regionCode', regionCode);
    url.searchParams.set('maxResults', String(maxResults));
    if (categoryId) url.searchParams.set('videoCategoryId', categoryId);
    url.searchParams.set('key', apiKey);

    const response = await fetch(url.toString());
    if (!response.ok) {
      const errBody = await response.json().catch(() => ({}));
      console.error('YouTube API error:', errBody);
      return res.status(502).json({ error: 'YouTube API error', details: errBody });
    }

    const data = await response.json() as { items?: YouTubeItem[] };
    const items: YouTubeItem[] = data.items || [];

    const videos = items.map((item) => ({
      id: item.id,
      title: item.snippet.title,
      channelTitle: item.snippet.channelTitle,
      channelId: item.snippet.channelId,
      thumbnail:
        item.snippet.thumbnails.maxres?.url ||
        item.snippet.thumbnails.high?.url ||
        item.snippet.thumbnails.medium?.url ||
        item.snippet.thumbnails.default?.url,
      publishedAt: item.snippet.publishedAt,
      viewCount: item.statistics?.viewCount || '0',
      likeCount: item.statistics?.likeCount || '0',
      duration: item.contentDetails?.duration || 'PT0S',
    }));

    const result = { videos, regionCode };
    await redis.setex(cacheKey, CACHE_TTL, JSON.stringify(result));

    return res.json(result);
  } catch (err) {
    console.error('YouTube trending error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
};

// GET /api/youtube/categories?regionCode=IN
export const getCategories = async (req: Request, res: Response) => {
  try {
    const apiKey = process.env.YOUTUBE_API_KEY;
    if (!apiKey) return res.status(503).json({ error: 'YouTube API not configured' });

    const rawRegion = (req.query.regionCode as string) || 'US';
    const regionCode = rawRegion.toUpperCase().slice(0, 2);
    const cacheKey = `youtube:categories:${regionCode}`;

    const cached = await redis.get(cacheKey);
    if (cached) return res.json(JSON.parse(cached));

    const url = new URL('https://www.googleapis.com/youtube/v3/videoCategories');
    url.searchParams.set('part', 'snippet');
    url.searchParams.set('regionCode', regionCode);
    url.searchParams.set('key', apiKey);

    const response = await fetch(url.toString());
    if (!response.ok) return res.status(502).json({ error: 'YouTube API error' });

    const data = await response.json() as { items?: any[] };
    const categories = (data.items || [])
      .filter((c: any) => c.snippet.assignable)
      .map((c: any) => ({ id: c.id, title: c.snippet.title }));

    const result = { categories, regionCode };
    await redis.setex(cacheKey, 86400, JSON.stringify(result)); // 24hr cache
    return res.json(result);
  } catch (err) {
    console.error('YouTube categories error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
};
