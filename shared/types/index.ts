// ==========================================
// WalletPro — Shared Type Definitions
// ==========================================
// These types are shared between the Flutter app (via equivalent Dart models)
// and the Node.js backend. Keep them in sync.

// ==========================================
// Wallet API Types (BudgetBakers)
// ==========================================

export interface WalletRecord {
  id: string;
  accountId: string;
  accountName: string;
  accountIsBankSync: boolean;
  amount: {
    currencyCode: string;
    value: number;
  };
  recordDate: string;
  recordType: 'expense' | 'income';
  recordState: 'reconciled' | 'cleared' | 'uncleared' | 'void' | 'waitForAssign';
  category: {
    id: string;
    name: string;
    color: string;
    group: {
      id: string;
      name: string;
    };
  };
  labels: Array<{
    id: string;
    name: string;
    color: string;
  }>;
  counterParty?: string;
  note?: string;
  source: 'android' | 'ios' | 'web' | 'rest' | 'mcp' | 'backend' | 'missing';
  transfer?: {
    type: 'paired' | 'unpaired';
    transferId: string;
    mirrorRecord?: {
      id: string;
      accountId: string;
      amount: { currencyCode: string; value: number };
      counterParty?: string;
      note?: string;
    };
  } | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateRecordRequest {
  accountId: string;
  amount: number; // negative = expense, positive = income
  recordDate: string; // ISO 8601
  categoryId?: string;
  counterParty?: string;
  note?: string;
  labelIds?: string[];
  recordState?: 'reconciled' | 'cleared' | 'uncleared';
}

export interface WalletAccount {
  id: string;
  name: string;
  accountType: string;
  currencyCode: string;
  color: string;
  bankAccountNumber?: string;
  isBankSync: boolean;
  isInvestmentAccount: boolean;
  excludeFromStats: boolean;
  archived: boolean;
  balance: {
    currencyCode: string;
    currentBalance: number;
    rawCurrentBalance: number;
    initial: number;
    balanceMode: string;
    formula: string;
  };
  recordStats: {
    recordCount: number;
    totalExpenses: number;
    totalIncomes: number;
    lastUpdatedAt?: string;
  };
  createdAt: string;
  updatedAt: string;
}

export interface WalletCategory {
  id: string;
  name: string;
  systemId?: string;
  customCategory: boolean;
  customName: boolean;
  parentId?: string;
  parentName?: string;
  cardinality: 'must' | 'need' | 'want' | 'none';
  color: string;
  group: {
    id: string;
    name: string;
  };
  enabled: boolean;
  archived: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface WalletBatchResult {
  summary: {
    total: number;
    succeeded: number;
    clientErrors: number;
    serverErrors: number;
    documentsWritten: number;
  };
  results: Array<{
    inputIndex: number;
    id: string;
    success: boolean;
    error?: string;
    fields?: string[];
    record?: WalletRecord;
  }>;
}

export interface WalletMeta {
  syncedAt: string;
  lastResourceChange?: {
    at: string;
    resource: string;
  };
  rateLimit: {
    remaining: number;
    capacity: number;
    refillPerMinute: number;
  };
}

// ==========================================
// Suggestion Types
// ==========================================

export type SuggestionSource = 'sms' | 'email' | 'portfolio' | 'nps';
export type SuggestionStatus = 'pending' | 'approved' | 'rejected' | 'synced' | 'expired';
export type TransactionType = 'expense' | 'income';

export interface Suggestion {
  id: string;
  source: SuggestionSource;
  status: SuggestionStatus;
  amount: number;
  currencyCode: string;
  transactionType: TransactionType;
  counterParty?: string;
  note?: string;
  referenceNumber?: string;
  accountLast4?: string;
  walletAccountId?: string;
  walletCategoryId?: string;
  walletCategoryName?: string;
  walletRecordId?: string;
  aiConfidence?: number;
  aiSuggestedCategory?: string;
  transactionDate: string;
  createdAt: string;
  actionedAt?: string;
}

export interface SuggestionStats {
  pending: number;
  approved: number;
  rejected: number;
  synced: number;
  expired: number;
  total: number;
}

// ==========================================
// Parsed Transaction Types
// ==========================================

export type TransactionMode = 'upi' | 'neft' | 'imps' | 'card' | 'netbanking' | 'atm' | 'unknown';

export interface ParsedTransaction {
  amount: number;
  transactionType: TransactionType;
  accountLast4?: string;
  counterParty?: string;
  referenceNumber?: string;
  balance?: number;
  transactionDate: string;
  source: 'sms' | 'email';
  rawText: string;
  confidence: number;
  bank?: string;
  transactionMode?: TransactionMode;
}

// ==========================================
// Portfolio Types
// ==========================================

export type HoldingType = 'mutual_fund' | 'stock' | 'nps';

export interface PortfolioHolding {
  id: string;
  type: HoldingType;
  name: string;
  code: string; // AMFI code / ISIN / PRAN
  units: number;
  avgCost: number;
  currentNav: number;
  currentValue: number;
  previousNav: number;
  changePercent: number;
  totalGainLoss: number;
  walletAccountId?: string;
  navUpdatedAt?: string;
}

export interface PortfolioSummary {
  totalValue: number;
  totalInvested: number;
  totalGainLoss: number;
  totalChangePercent: number;
  holdingsByType: {
    mutual_fund: { count: number; value: number };
    stock: { count: number; value: number };
    nps: { count: number; value: number };
  };
  lastUpdated?: string;
}

// ==========================================
// Insight Types
// ==========================================

export interface MonthlyBreakdown {
  month: string; // YYYY-MM
  totalExpenses: number;
  totalIncome: number;
  categorySummary: Array<{
    categoryId: string;
    categoryName: string;
    groupName: string;
    amount: number;
    count: number;
    color: string;
  }>;
}

export interface SpendingTrend {
  months: Array<{
    month: string;
    expenses: number;
    income: number;
  }>;
}

// ==========================================
// Category Group Constants
// ==========================================

export const WALLET_CATEGORY_GROUPS = [
  'communication_pc',
  'financial_expenses',
  'food_and_drinks',
  'housing',
  'income',
  'investments',
  'life_entertainment',
  'others',
  'shopping',
  'system_categories',
  'transportation',
  'unknown_records',
  'vehicle',
] as const;

export const FIXED_CATEGORY_IDS = {
  UNKNOWN_INCOME: '5c5c32c8-0082-8000-8000-000000000000',
  UNKNOWN_EXPENSE: '5c5c32c9-0082-8000-8000-000000000000',
  UNCATEGORIZED: '5c5c4e23-00c8-8000-8000-000000000000',
  TRANSFER: '5c5c4e21-00c8-8000-8000-000000000000',
} as const;
