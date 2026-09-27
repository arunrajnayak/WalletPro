import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
  PORT: z.string().default('3000'),
  DATABASE_URL: z.string().default('postgresql://postgres:postgres@localhost:5432/walletpro?schema=public'),
  JWT_SECRET: z.string().default('walletpro-personal-secret-key-change-me'),
  WALLET_API_BASE_URL: z.string().default('https://rest.budgetbakers.com/wallet'),
  WALLET_API_TOKEN: z.string().optional(),
  
  // Single-user / personal mode settings
  SINGLE_USER_MODE: z.string().default('true').transform(v => v === 'true' || v === '1'),
  PERSONAL_USER_ID: z.string().default('personal-user-001'),
  API_SECRET_KEY: z.string().optional(),
  CRON_SECRET: z.string().optional(),

  // Optional third-party integrations
  FIREBASE_PROJECT_ID: z.string().optional(),
  GOOGLE_CLIENT_ID: z.string().optional(),
  GOOGLE_CLIENT_SECRET: z.string().optional(),
  GEMINI_API_KEY: z.string().optional(),
});

const _env = envSchema.safeParse(process.env);

if (!_env.success) {
  console.error('❌ Invalid environment variables:', _env.error.format());
  throw new Error('Invalid environment variables');
}

export const env = _env.data;
