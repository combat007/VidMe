import { Router } from 'express';
import { getTrending, getCategories } from '../controllers/youtube.controller';

const router = Router();

router.get('/trending', getTrending);
router.get('/categories', getCategories);

export default router;
