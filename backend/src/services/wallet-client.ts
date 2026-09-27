import axios, { AxiosInstance } from 'axios';
import { env } from '../config/env';

export interface WalletRecord {
  id: string;
  accountId: string;
  accountName?: string;
  accountIsBankSync?: boolean;
  amount: { currencyCode: string; value: number } | number;
  recordDate: string;
  recordType: 'expense' | 'income';
  recordState: 'reconciled' | 'cleared' | 'uncleared';
  category?: { id: string; name: string; group?: { id: string; name: string }; color?: string };
  labels?: { id: string; name: string; color?: string }[];
  counterParty?: string;
  note?: string;
  source?: string;
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
  createdAt?: string;
  updatedAt?: string;
}

export interface CreateRecordRequest {
  accountId: string;
  amount: number | { value: number; currencyCode?: string }; // negative = expense, positive = income
  recordDate: string; // ISO 8601
  categoryId?: string;
  counterParty?: string;
  note?: string;
  labelIds?: string[];
  recordState?: 'reconciled' | 'cleared' | 'uncleared';
  transfer?: {
    pairingMode: 'new' | 'existing' | 'unpaired';
    accountId?: string;
    recordId?: string;
    counterAmount?: { value: number; currencyCode: string };
  };
}

export interface BatchResult {
  summary: {
    total: number;
    succeeded: number;
    clientErrors: number;
    serverErrors: number;
    documentsWritten?: number;
  };
  results: {
    inputIndex: number;
    id?: string;
    success: boolean;
    error?: string;
    fields?: string[];
    record?: any;
  }[];
}

export class WalletClient {
  private client: AxiosInstance;

  constructor(token: string) {
    this.client = axios.create({
      baseURL: `${env.WALLET_API_BASE_URL}/v1/api`,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      timeout: 15000,
      paramsSerializer: {
        indexes: null,
      },
    });
  }

  /**
   * Healthcheck / Verification: fetch accounts or usage stats
   */
  public async verifyConnection(): Promise<boolean> {
    try {
      const res = await this.client.get('/accounts', { params: { limit: 1 } });
      return res.status === 200;
    } catch (err) {
      return false;
    }
  }

  /**
   * List user's accounts (single page)
   */
  public async getAccounts(params?: { limit?: number; offset?: number; archived?: boolean }): Promise<any[]> {
    const res = await this.client.get('/accounts', { params });
    // In OpenAPI v2.0, accounts are returned directly or under an envelope
    return Array.isArray(res.data) ? res.data : (res.data.accounts || res.data.results || []);
  }

  /**
   * Fetch all user's accounts across all pages from BudgetBakers Wallet
   */
  public async getAllAccounts(options?: { archived?: boolean }): Promise<any[]> {
    const allAccounts: any[] = [];
    const limit = 20; // BudgetBakers Wallet API max account limit per request
    let offset = 0;
    let hasMore = true;
    let page = 0;
    const maxPages = 50; // Safety cap

    while (hasMore && page < maxPages) {
      page++;
      const res = await this.client.get('/accounts', {
        params: {
          limit,
          offset,
          ...(options?.archived !== undefined ? { archived: options.archived } : {}),
        },
      });

      const data = res.data;
      const accounts: any[] = Array.isArray(data)
        ? data
        : (data.accounts || data.results || []);

      allAccounts.push(...accounts);

      if (accounts.length < limit) {
        hasMore = false;
      } else if (data && typeof data.nextOffset === 'number') {
        offset = data.nextOffset;
      } else {
        offset += limit;
      }
    }

    return allAccounts;
  }

  /**
   * List all categories (base categories + custom subcategories)
   */
  public async getCategories(params?: { limit?: number; offset?: number }): Promise<any[]> {
    const res = await this.client.get('/categories', { params: { limit: 200, ...params } });
    return Array.isArray(res.data) ? res.data : (res.data.categories || res.data.results || []);
  }

  /**
   * List all labels
   */
  public async getLabels(params?: { limit?: number; offset?: number }): Promise<any[]> {
    const res = await this.client.get('/labels', { params });
    return Array.isArray(res.data) ? res.data : (res.data.labels || res.data.results || []);
  }

  /**
   * List all budgets
   */
  public async getBudgets(params?: { limit?: number; offset?: number }): Promise<any[]> {
    const res = await this.client.get('/budgets', { params });
    return Array.isArray(res.data) ? res.data : (res.data.budgets || res.data.results || []);
  }

  /**
   * Query records with filters
   */
  public async getRecords(filters?: any): Promise<WalletRecord[]> {
    const cleanFilters: any = {};
    if (filters) {
      for (const [key, value] of Object.entries(filters)) {
        if (value !== undefined && value !== null) {
          if (Array.isArray(value)) {
            cleanFilters[key] = value.length === 1 ? value[0] : value.join(',');
          } else {
            cleanFilters[key] = value;
          }
        }
      }
    }
    const res = await this.client.get('/records', { params: cleanFilters });
    return Array.isArray(res.data) ? res.data : (res.data.records || res.data.results || []);
  }

  /**
   * Create financial records in batch (1 to 50 records)
   * Official BudgetBakers REST API endpoint: POST /v1/api/records
   */
  public async createRecords(records: CreateRecordRequest[]): Promise<BatchResult> {
    // Standardize amount format to { value: number } as required by OpenAPI
    const formattedRecords = records.map(r => {
      const formatted: any = {
        ...r,
        amount: typeof r.amount === 'number' ? { value: r.amount } : r.amount,
        recordState: r.recordState || 'cleared',
      };
      // BudgetBakers requires categoryId to be omitted when transfer object is present
      if (r.transfer) {
        delete formatted.categoryId;
      }
      return formatted;
    });

    const res = await this.client.post('/records', formattedRecords);
    return res.data;
  }

  /**
   * Update financial records in batch (1 to 10 records)
   * Official BudgetBakers REST API endpoint: PATCH /v1/api/records
   */
  public async patchRecords(records: any[]): Promise<BatchResult> {
    const res = await this.client.patch('/records', records);
    return res.data;
  }

  /**
   * Delete records by ID
   * Official BudgetBakers REST API endpoint: DELETE /v1/api/records
   */
  public async deleteRecords(ids: string[]): Promise<any> {
    const res = await this.client.delete('/records', { data: { ids } });
    return res.data;
  }

  /**
   * Query API usage statistics
   */
  public async getApiUsageStats(period: string = '30days'): Promise<any> {
    const res = await this.client.get('/api-usage/stats', { params: { period } });
    return res.data;
  }
}
