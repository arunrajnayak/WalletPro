# WalletPro Setup Guide

## Prerequisites

### 1. BudgetBakers Wallet Pro
- Active Wallet Pro subscription
- REST API token with write permissions

### 2. Firebase Project
1. Create a new Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable **Authentication** → Google Sign-In
3. Enable **Cloud Messaging** (for push notifications)
4. Download `google-services.json` → `mobile/android/app/`
5. Download `GoogleService-Info.plist` → `mobile/ios/Runner/`

### 3. Google Cloud Project
1. Enable **Gmail API**
2. Enable **Cloud Pub/Sub API**
3. Create OAuth 2.0 credentials (Web Application type)
4. Add redirect URI: `https://your-backend-url/api/gmail/callback`
5. Create a Pub/Sub topic: `projects/YOUR_PROJECT/topics/gmail-notifications`
6. Grant Gmail publish permissions to the topic

### 4. Gemini API
1. Get an API key from [ai.google.dev](https://ai.google.dev)
2. Add to backend `.env` as `GEMINI_API_KEY`

### 5. Database (PostgreSQL)
**Option A: Supabase (Recommended for personal use)**
1. Create a free project at [supabase.com](https://supabase.com)
2. Copy the connection string from Settings → Database → Connection String (URI)

**Option B: Local PostgreSQL**
```bash
brew install postgresql@16
brew services start postgresql@16
createdb walletpro
```

## Backend Setup

```bash
cd backend

# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Edit .env with your credentials

# Push database schema
npx prisma db push

# Generate Prisma client
npx prisma generate

# Start development server
npm run dev
```

## Mobile App Setup

```bash
cd mobile

# Get Flutter dependencies
flutter pub get

# Run code generation (freezed, json_serializable)
dart run build_runner build --delete-conflicting-outputs

# Run on Android
flutter run

# Run on iOS (email-only features, no SMS)
flutter run -d ios
```

## Wallet API Token Setup

1. Open [web.budgetbakers.com/settings/mcp-server](https://web.budgetbakers.com/settings/mcp-server)
2. Under **Permissions**, enable:
   - `records.read` ✅
   - `records.create` ✅
   - `accounts.read` ✅
   - `categories.read` ✅
   - `labels.read` ✅
   - `budgets.read` ✅ (for insights)
3. Click **Generate Token**
4. Copy the token
5. In WalletPro app → Settings → Wallet Connection → Paste token

## Android: Enable Notification Access

1. Open WalletPro app
2. Go to Settings → Notification Access
3. Toggle ON "WalletPro" in system settings
4. This allows the app to read bank SMS notifications

> **Note:** This does NOT grant SMS read access. It only reads notification text as it arrives. No SMS history is accessed.

## Gmail Integration (Optional)

1. In WalletPro app → Settings → Gmail
2. Tap "Connect Gmail"
3. Sign in with your Google account
4. Grant "Read email" permission
5. The app will scan for bank transaction emails

> **Note:** For personal use (≤100 users), no Google CASA audit is needed. Stay in "Testing" mode in Google Cloud Console.

## Account Mapping

After connecting Wallet, map your bank accounts:

1. Go to Settings → Account Mapping
2. For each Wallet account, enter the **last 4 digits** of the bank account
3. This allows the SMS parser to match transactions to the correct Wallet account

Example:
- "HDFC Savings" → `1234`
- "ICICI Credit Card" → `5678`
- "SBI Current" → `9012`
