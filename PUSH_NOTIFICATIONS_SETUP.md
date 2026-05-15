# Push notifications (FCM) — one-time setup

Code is wired end-to-end. To activate real Android push notifications you must:

1. create a Firebase project,
2. drop credentials into the backend,
3. drop config into the Flutter app, and
4. rebuild.

Without those steps the system **still works** — the backend falls back to
simulation mode and the web frontend keeps using its WebSocket alert path.

---

## 1. Firebase Console

1. Open <https://console.firebase.google.com> → **Add project**. Pick a name
   like `eldercare`.
2. **Add Android app**:
   - Package name: `com.fyp.fyp_frontend` (matches
     `frontend/android/app/build.gradle.kts → applicationId`).
   - Skip the SHA-1 step for now.
   - Download `google-services.json`.
3. **Service account**: Project Settings → Service accounts → **Generate new
   private key**. Save the JSON.

---

## 2. Backend credentials

Drop the service-account JSON at:

```
backend/credentials/fcm-service-account.json
```

This file is `.gitignore`d. The path is mounted into the backend container by
`docker-compose.yml` at `/app/credentials/fcm-service-account.json`, and the
default `FCM_CREDENTIALS_PATH` already points there.

Restart the backend:

```
docker compose restart backend
```

You should see `Firebase Admin initialized for FCM push dispatch` in the logs
on first push attempt. If you keep seeing `push dispatch will run in
simulation mode`, the JSON is missing or unreadable.

---

## 3. Flutter / Android config

### Option A — automated (recommended)

```
cd frontend
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project-id> --platforms=android,web
```

This:

- generates `frontend/lib/firebase_options.dart` with real values, replacing
  the placeholder shipped in the repo,
- drops `frontend/android/app/google-services.json` (already gitignored).

### Option B — manual

- Save `google-services.json` from Firebase Console at
  `frontend/android/app/google-services.json`.
- Edit `frontend/lib/firebase_options.dart` to return real `FirebaseOptions`
  for Android instead of `null`.

Then:

```
flutter pub get
flutter run -d <android-device-id>
```

---

## 4. Verify end-to-end

1. **Sign in** on the Android device. The Account screen → **Push
   notifications** card should now show a green **Registered** badge. If you
   see the "Mobile push is available… once Firebase is configured" notice,
   `firebase_options.dart` is still the stub — re-run step 3.
2. Check the backend DB:
   ```sql
   SELECT id, user_id, platform, is_active FROM device_tokens ORDER BY id DESC LIMIT 5;
   ```
   You should see a row with `platform=fcm`.
3. **Send a test push**: tap "Send test" on the Account → Notifications card.
   The message banner should report `Push delivered to 1 device(s).` and a
   system-tray notification should arrive.
4. **End-to-end alert**: trigger an incident manually (replace token):
   ```
   curl -X POST http://localhost:8000/api/incidents/ \
     -H "Authorization: Bearer <your-token>" \
     -H "Content-Type: application/json" \
     -d '{"event_type":"fall","severity":"critical","status":"new","patient_id":1}'
   ```
   The phone should buzz with `FALL detected — <patient name>`. Tap the
   notification → app opens directly to the Incidents screen.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Backend log says `FCM_CREDENTIALS_PATH not set`. | `.env` not picked up. Verify env var or path in `docker-compose.yml`. |
| Backend log says `FCM credentials file not found`. | The mounted volume is empty; place the JSON at `backend/credentials/fcm-service-account.json`. |
| Flutter build fails with `google-services.json is missing`. | Either run `flutterfire configure` or place the file manually at `frontend/android/app/google-services.json`. |
| App builds but `Push notifications` card stays in simulated state. | `firebase_options.dart` still returns null — overwrite it via `flutterfire configure`. |
| Notification arrives but tapping it doesn't open the right screen. | Ensure `data.incident_id` is sent (it is, by `push_service.py`) and that you're running the Flutter build that includes the `AppShell` tap subscription. |
| Receive duplicate notifications on the same device. | Web tab and mobile both subscribed; expected when the same user is signed in twice. The app dedupes the in-app list by `incident_id`. |

---

## What's wired in the codebase already

**Backend**
- `backend/app/services/push_service.py` – Firebase Admin SDK wrapper with
  scope resolution (admins + caregiver + relative).
- `backend/app/routes/notifications.py` – `/test` endpoint now dispatches via
  `push_service` (real FCM when configured; otherwise simulated).
- `backend/app/services/result_processor.py` – queues a push per incident
  alongside the existing Redis publish; sends after commit.
- `backend/app/config.py` – new `fcm_credentials_path` setting.
- `docker-compose.yml` – mounts `./backend/credentials` and sets
  `FCM_CREDENTIALS_PATH` env var.

**Frontend**
- `lib/services/push_service.dart` – initialization, token registration,
  foreground handler, tap-to-deep-link.
- `lib/services/auth_controller.dart` – calls `ensurePermissionAndRegister`
  on login, `deactivateOnLogout` on logout.
- `lib/services/incident_stream_service.dart` – `injectIncidentEvent` API so
  foreground FCM messages also drive the in-app badge.
- `lib/widgets/app_shell.dart` – listens for tap-to-deep-link and switches to
  the Incidents screen.
- `lib/screens/account/account_screen.dart` – Notifications card.

**Android**
- `android/settings.gradle.kts` – Google services plugin declared.
- `android/app/build.gradle.kts` – plugin applied, `minSdk = 23`,
  `multiDexEnabled = true`.
- `android/app/src/main/AndroidManifest.xml` – `POST_NOTIFICATIONS`,
  `WAKE_LOCK`, default notification icon + channel id meta-data,
  `FLUTTER_NOTIFICATION_CLICK` intent filter on the launcher activity.
