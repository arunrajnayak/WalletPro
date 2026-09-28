import { Router, Request, Response } from 'express';
import axios from 'axios';

const router = Router();

interface CachedRelease {
  data: any;
  cachedAt: number;
}

let cachedRelease: CachedRelease | null = null;
const CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes

/**
 * GET /api/app/latest-release
 * Fetches latest GitHub release info for WalletPro with in-memory caching.
 */
router.get('/latest-release', async (_req: Request, res: Response) => {
  const now = Date.now();
  if (cachedRelease && (now - cachedRelease.cachedAt < CACHE_TTL_MS)) {
    return res.json(cachedRelease.data);
  }

  try {
    const response = await axios.get(
      'https://api.github.com/repos/arunrajnayak/WalletPro/releases/latest',
      {
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'WalletPro-Backend'
        },
        timeout: 8000
      }
    );

    const release = response.data;
    const assets = release.assets || [];
    const apkAsset = assets.find((a: any) =>
      a.name?.endsWith('.apk') || a.content_type === 'application/vnd.android.package-archive'
    );

    const formattedData = {
      tagName: release.tag_name || '',
      version: (release.tag_name || '').replace(/^v/, ''),
      name: release.name || release.tag_name || '',
      body: release.body || '',
      publishedAt: release.published_at || '',
      apkName: apkAsset?.name || '',
      apkSize: apkAsset?.size || 0,
      apkDownloadUrl: apkAsset?.browser_download_url || '',
      raw: release
    };

    cachedRelease = {
      data: formattedData,
      cachedAt: now
    };

    return res.json(formattedData);
  } catch (error: any) {
    if (cachedRelease) {
      // Serve stale cache if GitHub is unreachable
      return res.json(cachedRelease.data);
    }
    return res.status(502).json({
      error: 'Failed to fetch release info from GitHub',
      details: error.message
    });
  }
});

export default router;
