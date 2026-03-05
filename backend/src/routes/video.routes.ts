import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware';
import { uploadVideo, uploadThumbnail, uploadChunk as uploadChunkMiddleware } from '../middleware/upload.middleware';
import {
  uploadVideoFile,
  uploadThumbnailFile,
  uploadChunk,
  finalizeChunkedUpload,
  getFinalizeStatus,
  createVideo,
  listVideos,
  getVideo,
  updateVideo,
  deleteVideo,
  searchSuggestions,
} from '../controllers/video.controller';

const router = Router();

// Suggestions (must be before /:id to avoid route conflict)
router.get('/suggestions', (req, res) => searchSuggestions(req as any, res));

// Public (with optional auth for 18+ filtering)
router.get('/', (req, res, next) => {
  // Optionally authenticate but don't require it
  const auth = req.headers.authorization;
  if (auth) {
    return authenticate(req as any, res, () => listVideos(req as any, res));
  }
  return listVideos(req as any, res);
});

router.get('/:id', (req, res) => {
  const auth = req.headers.authorization;
  if (auth) {
    return authenticate(req as any, res, () => getVideo(req as any, res));
  }
  return getVideo(req as any, res);
});

// Protected
router.post('/upload', authenticate, uploadVideo.single('video'), (req, res) =>
  uploadVideoFile(req as any, res)
);
router.post('/upload-chunk', authenticate, uploadChunkMiddleware.single('chunk'), (req, res) =>
  uploadChunk(req as any, res)
);
router.post('/finalize-upload', authenticate, (req, res) =>
  finalizeChunkedUpload(req as any, res)
);
router.get('/finalize-status/:jobId', authenticate, (req, res) =>
  getFinalizeStatus(req as any, res)
);
router.post('/upload-thumbnail', authenticate, uploadThumbnail.single('thumbnail'), (req, res) =>
  uploadThumbnailFile(req as any, res)
);
router.post('/', authenticate, (req, res) => createVideo(req as any, res));
router.patch('/:id', authenticate, (req, res) => updateVideo(req as any, res));
router.delete('/:id', authenticate, (req, res) => deleteVideo(req as any, res));

export default router;
