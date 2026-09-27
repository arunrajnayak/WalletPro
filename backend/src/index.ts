import app from './app';
import { env } from './config/env';
import { startCleanupWorker } from './workers/cleanup-worker';

const PORT = env.PORT || 3000;

// In local mode (not running as a Vercel serverless function), start background workers
if (process.env.VERCEL !== '1') {
  startCleanupWorker();
}

app.listen(PORT, () => {
  console.log(`🚀 WalletPro server running on port ${PORT}`);
  console.log(`👤 Single-User Mode: ${env.SINGLE_USER_MODE ? 'Enabled (personal use)' : 'Disabled'}`);
  console.log(`💰 BudgetBakers Base URL: ${env.WALLET_API_BASE_URL}`);
});
