# Firebase Push Notifications — Setup Guide

The app code is **fully wired** for FCM push notifications. All you need to do is:
1. Create a free Firebase project
2. Drop a credentials file into the right folder
3. Rebuild the APK

Everything else — permissions, channels, foreground/background handlers, deep-linking from notification tap → Incidents screen — is already in the codebase and will activate automatically once Firebase has real credentials.

Time required: **~10 minutes** for the Firebase side, ~2 minutes to rebuild.

---

## Step 1 — Create the Firebase project

1. Go to **<https://console.firebase.google.com>** and sign in with any Google account
2. Click **Add project**
3. Project name: anything (e.g. `eldercare`). Click **Continue**
4. Google Analytics: turn it **off** (not needed). Click **Create project**, wait ~30 seconds

## Step 2 — Register your Android app

1. On the project's overview page, click the **Android** icon
2. **Android package name**: type exactly `com.fyp.fyp_frontend`
3. **App nickname**: `Eldercare` (or skip)
4. **SHA-1 certificate**: skip — not needed for FCM
5. Click **Register app**
6. **Download `google-services.json`** when prompted
7. Move that file to:
   ```
   c:\Users\PC\Documents\GitHub\FYP\frontend\android\app\google-services.json
   ```
8. On the next Firebase screen ("Add Firebase SDK"), click **Next** → **Next** → **Continue to console**. We've already added everything in code; no manual SDK steps needed.

## Step 3 — Backend service-account key

The backend needs credentials to send notifications to Firebase. This is a separate file from `google-services.json`.

1. In Firebase Console, click the **gear icon** ⚙️ next to "Project Overview" → **Project settings**
2. Open the **Service accounts** tab
3. Click **Generate new private key** → **Generate key**
4. A JSON file downloads — rename it to **`fcm-service-account.json`**
5. Place it at:
   ```
   c:\Users\PC\Documents\GitHub\FYP\backend\credentials\fcm-service-account.json
   ```
   (Create the `credentials/` folder if it doesn't exist — it's gitignored by default.)
6. Restart the backend:
   ```powershell
   docker compose restart backend
   ```
7. Check the backend log — you should see `Firebase Admin initialized` (instead of "simulation mode"):
   ```powershell
   docker compose logs backend --tail 30
   ```

## Step 4 — Rebuild the APK

```powershell
cd c:\Users\PC\Documents\GitHub\FYP
.\build_apk.ps1
```

Or manually:

```powershell
cd c:\Users\PC\Documents\GitHub\FYP\frontend
flutter build apk --release `
  --dart-define=API_BASE_URL=https://your-tunnel.trycloudflare.com `
  --dart-define=WS_BASE_URL=wss://your-tunnel.trycloudflare.com
```

When the build runs, you'll see:
```
✅ google-services.json detected — Firebase Cloud Messaging enabled.
```
instead of the "not found" warning. That confirms it picked up the credentials.

## Step 5 — Test it

1. Install the new APK on your phone
2. Open the app, log in, go to **More → Account → Push notifications**
3. Tap **Enable on this device**. Android will ask for notification permission (Android 13+)
4. The card should now show **"Registered"** with a green badge
5. Tap **Send test**. Within a few seconds, a notification slides into your phone's notification tray
6. Tap the notification → app opens directly to the **Incidents** screen
7. **Trigger a real incident** (run any detection that finds a fall/seizure). The phone will get a push automatically

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails: `google-services.json missing` | File in wrong place | Verify at `frontend/android/app/google-services.json` |
| App boots, but "Push not available" in Account | `firebase_options.dart` still a stub | Run `flutterfire configure` (see below) OR use the alternate setup below |
| `Enable on device` works, but no notification arrives | Backend doesn't have service-account | Check `docker compose logs backend` for `Firebase Admin initialized` |
| Notification arrives, tap does nothing | Cold-start payload not captured | Already handled in code — file a bug if you see this |
| Duplicate notifications | Both foreground display + FCM tray firing | App already debounces — rebuild from clean (`flutter clean && flutter build`) |

### Alternate setup using `flutterfire configure`

Instead of dragging `google-services.json` manually, you can run:

```powershell
dart pub global activate flutterfire_cli
cd c:\Users\PC\Documents\GitHub\FYP\frontend
flutterfire configure --project=<your-firebase-project-id> --platforms=android
```

This auto-generates `lib/firebase_options.dart` AND places `google-services.json` for you. Use this path if you also want iOS support later (add `,ios` to `--platforms`).

---

## What's already in the codebase

You don't need to touch any of this — it's listed here just so you know what's wired up:

| File | What it does |
|---|---|
| `frontend/lib/services/push_service.dart` | Boots FCM, requests permission, registers device token, handles foreground/background/cold-start messages, deep-links to Incidents on tap |
| `frontend/lib/firebase_options.dart` | Placeholder — replaced by `flutterfire configure` |
| `frontend/android/app/build.gradle.kts` | Conditional Firebase plugin — activates only when `google-services.json` is present |
| `frontend/android/app/src/main/AndroidManifest.xml` | POST_NOTIFICATIONS permission, default notification channel "eldercare_alerts", `FLUTTER_NOTIFICATION_CLICK` intent filter |
| `backend/app/routes/notifications.py` | `/api/notifications/devices` for token registration, `/api/notifications/test` for test sends |
| `backend/app/services/push_service.py` | Sends FCM via the Admin SDK (or simulates if creds missing) |
| `frontend/lib/screens/account/account_screen.dart` | UI to enable on device + send test notification |

---

## Why two credential files?

- **`google-services.json`** lives in the *Android app* — tells the phone "this is the Firebase project I belong to". Public-ish (it's bundled into every APK).
- **`fcm-service-account.json`** lives on the *backend* — gives the backend permission to *send* notifications on behalf of the Firebase project. **Secret** — never commit to git, never bundle into the APK.

The `.gitignore` already excludes both. If you accidentally commit either, rotate them in Firebase Console.
