# Privacy Policy

**Last updated: August 6, 2026**

The PolyDev app (the "App") is developed by xApi Devs, an independent developer ("we", "us"). This Policy describes what data we collect, how we use it, and how we store it.

## 1. What data we collect

### 1.1. Account data
When you sign in via Google/Firebase Authentication, we receive and store server-side (in Firestore): your email address, display name, avatar URL, account creation and last-login dates, and a unique device identifier — used solely to enforce the limit on how many devices can be active at once on your plan.

### 1.2. Subscription data
We use RevenueCat to process purchases and subscriptions, which in turn communicates with the App Store/Google Play. We store your subscription status (tier, active entitlements, renewal date) in our database to unlock the corresponding features in the app. We never receive or store your payment card details — billing is handled entirely by Apple/Google.

### 1.3. Data that stays on your device only
The contents of your projects, code, chat history with the AI agent, third-party AI provider API keys and access tokens, and GitHub/Vercel/Cloudflare Pages access tokens are stored **locally on your device** (in encrypted local storage) and are **never transmitted to or stored on our servers**. We have no technical access to this data.

### 1.4. Data sent to third-party AI providers
If you use your own API key (OpenAI, Anthropic, Google, etc.), the contents of your requests (messages, code) are sent directly to the provider you chose and are handled under that provider's own privacy policy — we do not act as an intermediary and never see the contents of those requests. If you use the app's built-in AI provider, requests are routed through our proxy (OpenRouter) — we do not retain the contents of such requests any longer than needed to process them.

### 1.5. GitHub, Vercel, Cloudflare Pages
If you connect your GitHub, Vercel, or Cloudflare Pages account, the corresponding access token is stored locally on your device only and is used exclusively to perform actions you initiate yourself (pushing code, deploying). We never receive a copy of this token on our servers.

### 1.6. Push notifications and news likes
If you allow push notifications, we obtain a Firebase Cloud Messaging device token and subscribe it to the news topic — used solely to deliver notifications about new items in the news section. If you like a news item, we store that fact (which items you liked) in our database, tied to your account.

### 1.7. Usage statistics
We use Firebase Analytics (Google) to understand which app features are used: opening the app, creating a project, sending a message to the agent, deploying, and the type of AI provider chosen. Anonymous events, an app-installation identifier and general device data (model, OS version, language, country) are collected. We do **not** send message text, code, file names, keys or tokens there. The advertising ID is not used. You can turn statistics off in Settings → “Usage statistics”.

## 2. How we use data

We use the data we collect to:
- Authenticate you and sync your subscription status across your devices;
- Unlock features according to your paid plan;
- Enforce the limit on simultaneously active devices per subscription;
- Show the in-app news section;
- Respond to your support requests.

We do not show ads and do not sell or share your personal data with third parties for marketing purposes.

## 3. Data retention and deletion

Account data (sections 1.1–1.2) is retained while your account is active. You can request full deletion of your account and associated server-side data by writing to support@polydev.app. Local data (projects, chat history, API keys) is removed immediately when you uninstall the app or clear it manually from the app's settings.

## 4. Children

The app is not directed at children under 13, and we do not knowingly collect data from them.

## 5. Security

We use industry-standard safeguards (encryption in transit, secure local storage for secrets), but we cannot guarantee absolute protection against every possible threat.

## 6. Changes to this Policy

We may update this Policy from time to time. Material changes will be reflected in this document with an updated date at the top.

## 7. Contact

For questions about this Policy, contact: support@polydev.app
