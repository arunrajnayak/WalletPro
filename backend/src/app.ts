import express, { Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { errorHandler } from './middleware/errorHandler';

import authRoutes from './routes/auth.routes';
import walletRoutes from './routes/wallet.routes';
import suggestionsRoutes from './routes/suggestions.routes';
import portfolioRoutes from './routes/portfolio.routes';
import insightsRoutes from './routes/insights.routes';
import cronRoutes from './routes/cron.routes';
import appRoutes from './routes/app.routes';

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());

// Healthcheck
app.get('/', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    name: 'WalletPro Automation Assistant API',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

app.get('/api/health', (_req: Request, res: Response) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Mount modular routes
app.use('/api/auth', authRoutes);
app.use('/api/wallet', walletRoutes);
app.use('/api/suggestions', suggestionsRoutes);
app.use('/api/portfolio', portfolioRoutes);
app.use('/api/insights', insightsRoutes);
app.use('/api/cron', cronRoutes);
app.use('/api/app', appRoutes);

// Global Error Handler
app.use(errorHandler);

export default app;
