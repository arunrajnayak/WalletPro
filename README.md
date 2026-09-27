# 💰 WalletPro

> An intelligent automation assistant for [BudgetBakers Wallet](https://budgetbakers.com/) that auto-detects transactions from SMS & email, tracks investment portfolios, and posts approved entries to Wallet.

## ✨ Features

- **📱 SMS Transaction Detection** — Automatically detects bank transactions via Android NotificationListenerService
- **📧 Email Parsing** — Syncs transaction emails from Gmail (HDFC, ICICI, SBI, Axis, Kotak, etc.)
- **🔄 Smart Dedup** — 3-layer duplicate detection prevents SMS+email duplicates
- **✅ Suggestion Queue** — Swipeable card UI for approving/rejecting transactions
- **🤖 AI Categorization** — Gemini-powered category suggestions with learning loop
- **📊 Portfolio Tracking** — Mutual Funds (via mfapi.in), Stocks, NPS value tracking
- **📈 Spending Insights** — Monthly breakdowns, trends, and budget alerts
- **🔐 Privacy-First** — SMS parsed on-device; only structured data sent to backend

## 🏗️ Architecture

```
WalletPro/
├── mobile/          # Flutter app (Android/iOS)
├── backend/         # Node.js + TypeScript API server
├── shared/          # Shared type definitions
└── docs/            # Documentation
```

## 🚀 Quick Start

### Prerequisites

- Flutter 3.x ([install](https://flutter.dev/docs/get-started/install))
- Node.js 20+ ([install](https://nodejs.org/))
- PostgreSQL (or [Supabase](https://supabase.com/) free tier)
- BudgetBakers Wallet Pro subscription
- Firebase project (for auth & messaging)

### Backend Setup

```bash
cd backend
cp .env.example .env
# Edit .env with your credentials
npm install
npx prisma db push
npm run dev
```

### Mobile App Setup

```bash
cd mobile
flutter pub get
flutter run
```

### Wallet API Setup

1. Go to [web.budgetbakers.com/settings/mcp-server](https://web.budgetbakers.com/settings/mcp-server)
2. Enable `records.create`, `records.read`, `accounts.read`, `categories.read` scopes
3. Generate an API token
4. Enter the token in WalletPro Settings

## 📱 Supported Banks (SMS Parsing)

| Bank | UPI | NEFT/IMPS | Card | ATM |
|------|-----|-----------|------|-----|
| HDFC Bank | ✅ | ✅ | ✅ | ✅ |
| ICICI Bank | ✅ | ✅ | ✅ | ✅ |
| SBI | ✅ | ✅ | ✅ | ✅ |
| Axis Bank | ✅ | ✅ | ✅ | ✅ |
| Kotak Mahindra | ✅ | ✅ | ✅ | ✅ |
| PNB | ✅ | ✅ | ✅ | ✅ |
| Bank of Baroda | ✅ | ✅ | ✅ | ✅ |
| IndusInd Bank | ✅ | ✅ | ✅ | ✅ |
| Yes Bank | ✅ | ✅ | ✅ | ✅ |

## 🔒 Privacy & Security

- SMS is parsed **entirely on-device** — raw text never leaves your phone
- Only structured transaction data (amount, merchant, date) is sent to the backend
- Wallet API token is encrypted at rest
- Gmail OAuth uses minimal `gmail.readonly` scope
- All data transfer over TLS

## 📄 License

MIT
