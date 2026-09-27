import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
  });

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}

let dbConstraintChecked = false;

/**
 * Safely ensure obsolete foreign key constraints are removed from Postgres.
 * Specifically drops `suggestions_wallet_account_id_fkey` which incorrectly linked
 * `suggestions.wallet_account_id` (an external BudgetBakers ID string) to `wallet_accounts.id` (internal DB UUID).
 */
export async function ensureDbConstraints(): Promise<void> {
  if (dbConstraintChecked) return;
  try {
    await prisma.$executeRawUnsafe(`
      ALTER TABLE "suggestions" DROP CONSTRAINT IF EXISTS "suggestions_wallet_account_id_fkey";
    `);
    dbConstraintChecked = true;
  } catch (err: any) {
    console.warn('Note: suggestions_wallet_account_id_fkey cleanup check:', err?.message || err);
  }
}

export default prisma;
