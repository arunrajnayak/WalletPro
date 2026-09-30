import { GoogleGenerativeAI } from '@google/generative-ai';
import { prisma } from '../prisma';
import { env } from '../config/env';

export class CategoryAI {
  private genAI: GoogleGenerativeAI | null = null;

  constructor() {
    if (env.GEMINI_API_KEY && env.GEMINI_API_KEY.trim().length > 0) {
      try {
        this.genAI = new GoogleGenerativeAI(env.GEMINI_API_KEY);
      } catch (err) {
        console.warn('Could not initialize GoogleGenerativeAI:', err);
      }
    }
  }

  /**
   * Suggests a category based on transaction details and user's past categorization habits.
   */
  public async suggestCategory(
    userId: string,
    counterParty: string,
    amount: number,
    type: 'income' | 'expense'
  ): Promise<{ categoryId: string | null; categoryName?: string; confidence: number }> {
    // 1. Check local learning history first
    if (counterParty && counterParty.trim().length > 0) {
      const normalized = counterParty.trim().toLowerCase();
      const history = await prisma.merchantCategory.findUnique({
        where: { userId_merchantName: { userId, merchantName: normalized } }
      });
      if (history) {
        return {
          categoryId: history.walletCategoryId,
          categoryName: history.walletCategoryName || undefined,
          confidence: 0.95
        };
      }

      // Partial match fallback for merchant names (e.g. "Swiggy Instamart" -> "swiggy")
      const partial = await prisma.merchantCategory.findFirst({
        where: {
          userId,
          merchantName: { contains: normalized, mode: 'insensitive' }
        },
        orderBy: { usageCount: 'desc' }
      });
      if (partial) {
        return {
          categoryId: partial.walletCategoryId,
          categoryName: partial.walletCategoryName || undefined,
          confidence: 0.85
        };
      }
    }

    // 2. Fall back to Gemini AI if available
    if (this.genAI && counterParty) {
      try {
        // Fetch cached categories to provide exact IDs to Gemini
        const categories = await prisma.walletCategoryCache.findMany({
          where: { userId },
          select: { walletCategoryId: true, name: true, groupName: true }
        });

        if (categories.length > 0) {
          const model = this.genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
          const categoryList = categories.map(c => `ID: ${c.walletCategoryId}, Name: "${c.name}", Group: "${c.groupName}"`).join('\n');

          const prompt = `You are a financial transaction categorization assistant.
Match this transaction to the single most appropriate category ID from the list below.

Transaction:
Type: ${type}
Amount: INR ${amount}
Merchant / Payee: "${counterParty}"

Categories available:
${categoryList}

Respond strictly in valid JSON format:
{"categoryId": "chosen_id", "confidence": 0.85, "reasoning": "brief reason"}`;

          const result = await model.generateContent(prompt);
          const text = result.response.text();
          const jsonMatch = text.match(/\{[\s\S]*\}/);
          if (jsonMatch) {
            const parsed = JSON.parse(jsonMatch[0]);
            const matchedCategory = categories.find(c => c.walletCategoryId === parsed.categoryId);
            return {
              categoryId: parsed.categoryId || null,
              categoryName: matchedCategory?.name,
              confidence: parsed.confidence || 0.8
            };
          }
        }
      } catch (err) {
        console.warn('Gemini categorization error (falling back):', err);
      }
    }

    return { categoryId: null, confidence: 0 };
  }

  /**
   * Records user category selection to continuously improve accuracy.
   */
  public async recordCategorySelection(
    userId: string,
    merchantName: string,
    walletCategoryId: string,
    walletCategoryName?: string
  ) {
    if (!merchantName || !merchantName.trim()) return;
    const normalized = merchantName.trim().toLowerCase();

    await prisma.merchantCategory.upsert({
      where: { userId_merchantName: { userId, merchantName: normalized } },
      update: { 
        walletCategoryId, 
        walletCategoryName: walletCategoryName || undefined,
        usageCount: { increment: 1 },
        lastUsed: new Date()
      },
      create: {
        userId,
        merchantName: normalized,
        walletCategoryId,
        walletCategoryName: walletCategoryName || undefined,
      }
    });
  }
}
