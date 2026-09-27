# Deploying WalletPro Backend to Vercel (Personal Use)

This backend is optimized for single-user personal deployment on Vercel with zero maintenance.

---

## 1. Prerequisites

1. **GitHub Account** (to push the repository)
2. **Vercel Account** (free hobby tier is 100% sufficient)
3. **PostgreSQL Database** (e.g., [Supabase](https://supabase.com/) or [Neon](https://neon.tech/) — both free)
4. **BudgetBakers Wallet API Token** (from [web.budgetbakers.com/settings/mcp-server](https://web.budgetbakers.com/settings/mcp-server))

---

## 2. Deploy in 4 Steps

### Step 1: Push Repository to GitHub

```bash
git add .
git commit -m "feat: complete WalletPro for personal Vercel deployment"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/WalletPro.git
git push -u origin main
```

### Step 2: Import Project in Vercel

1. In Vercel Dashboard, click **Add New** → **Project**.
2. Select your `WalletPro` repository.
3. In **Root Directory**, click Edit and select: `backend`.
4. Leave Framework Preset as **Other** (or Express).

### Step 3: Configure Environment Variables

Add the following environment variables in Vercel:

| Variable | Value | Description |
| :--- | :--- | :--- |
| `DATABASE_URL` | `postgresql://...` | Connection string to your PostgreSQL DB (Supabase / Neon) |
| `SINGLE_USER_MODE` | `true` | Enables zero-friction single personal user mode |
| `WALLET_API_TOKEN` | `your_token_here` | Your BudgetBakers Wallet REST API token |
| `API_SECRET_KEY` | `your_chosen_secret` | (Optional) Secret key to pass in `x-api-key` header |
| `CRON_SECRET` | `your_cron_secret` | (Optional) Secures automated daily cron jobs |
| `GEMINI_API_KEY` | `your_gemini_key` | (Optional) For AI category suggestion from Google AI |

### Step 4: Deploy & Initialize Database

1. Click **Deploy**.
2. Once deployed, run the initial database schema push from your local terminal or GitHub Action:
   ```bash
   cd backend
   DATABASE_URL="your_production_postgres_url" npx prisma db push
   ```

---

## 3. Automated Vercel Crons

The provided `backend/vercel.json` automatically configures two daily cron jobs on Vercel:

1. **Daily NAV & Portfolio Refresh (`/api/cron/nav`)**:
   - Runs daily at 11:00 UTC (4:30 PM IST, right after Indian market close).
   - Fetches latest Mutual Fund NAVs from `mfapi.in` and generates value update suggestions in your app queue.
2. **Expired Suggestions Cleanup (`/api/cron/cleanup`)**:
   - Runs daily at midnight UTC to mark unresolved suggestions older than 30 days as expired.

---

## 4. Connecting the Mobile App

In the Flutter app or via `mobile/lib/core/constants/api_constants.dart`:

```dart
static const String backendBaseUrl = 'https://your-walletpro-deployment.vercel.app';
```

Or pass it as a compile-time environment variable:
```bash
flutter run --dart-define=BACKEND_URL=https://your-walletpro-deployment.vercel.app
```
