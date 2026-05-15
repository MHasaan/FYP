# Backend credentials

Drop your Firebase service-account JSON file here as
`fcm-service-account.json` to enable real push notification delivery via FCM.

How to obtain it:

1. Open https://console.firebase.google.com and select (or create) the project.
2. Project Settings → Service accounts → "Generate new private key".
3. Save the resulting JSON as `backend/credentials/fcm-service-account.json`.
4. Confirm `FCM_CREDENTIALS_PATH=/app/credentials/fcm-service-account.json` is
   set in `.env` (or rely on the default in `docker-compose.yml`).
5. Restart the backend container.

While the file is missing the backend automatically falls back to simulation
mode — REST endpoints still respond, but no real FCM messages are sent.

This file is gitignored. Never commit credentials.
