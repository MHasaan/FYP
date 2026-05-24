# Web + Mobile App — Run Commands

Complete instructions for running Eldercare locally on your laptop and on a phone, starting from a freshly turned-on PC.

> **One codebase note:** Flutter compiles **the same `frontend/` code** into a web app (browser) AND an Android APK (phone). When you change a `.dart` file, both surfaces change. The UI adapts to screen size — wide → desktop layout, narrow → mobile layout.

---

## TL;DR — pick your goal

| I want to… | Run this | Time |
|---|---|---|
| Code + see changes live in browser | `.\dev.ps1` | 30 sec |
| See the web app as users see it (production build) | `docker compose up -d` then open `http://localhost` | 1 min first time |
| Share the web app over the public internet | Cloudflare tunnel (Mode 2 below) | 2 min |
| Build APK for my own phone on home Wi-Fi | `.\build_apk.ps1 -Url http://<laptop-ip>:8000` | 2-5 min |
| Build APK that anyone can install + use | Tunnel + `.\build_apk.ps1 -Url <tunnel-url>` | 5 min |
| Code on phone with hot reload (no APK) | `.\dev.ps1 phone` (phone plugged in via USB) | 30 sec |

---

## Daily startup checklist

Every time you turn the PC on, do these in order:

### 1. Start Docker Desktop

Open the Docker Desktop app from the Start menu. Wait until the whale icon in your system tray **stops animating** (~30-60 sec).

### 2. Bring up the backend stack

```powershell
cd c:\Users\PC\Documents\GitHub\FYP
docker compose up -d
```

This starts: PostgreSQL database, Redis, FastAPI backend, ML manager, and the production Flutter web app served via Nginx.

First time per PC reboot: ~1 minute. After that: ~10 seconds.

### 3. Verify the backend is alive

```powershell
Invoke-WebRequest http://localhost:8000/health
```

Should print `{"status":"ok",...}`. If yes, you're ready.

### 4. (Optional) Check containers

```powershell
docker compose ps
```

Should show 5 containers, all "running" or "healthy".

---

## Mode 1: Web app locally (no Cloudflare needed)

### Option A — Production-style (what Docker builds)

```powershell
docker compose up -d
# Open browser to:  http://localhost
```

- **Pros:** Same Nginx build users would get. No Flutter SDK needed in your shell.
- **Cons:** Code changes need a `docker compose up -d --build frontend` rebuild (~2 min each).
- **Use for:** Sanity-checking the final product. Showing it to non-coders.

### Option B — Dev with hot reload (FAST coding)

```powershell
.\dev.ps1
```

- Chrome opens automatically at `http://localhost:8080`
- Edit any `.dart` file → save → see changes in **~500 ms**
- In the terminal: press `r` (hot reload), `R` (hot restart), or `q` (quit)
- **Use for:** Anything you're actively coding.

⚠️ The dev server uses port **8080** specifically because that port is in the backend's `CORS_ORIGINS`. Don't change it unless you also add the new port to `.env`.

---

## Mode 2: Web app shared with the world (Cloudflare tunnel)

Use this when you want a friend / panel / family member to load the web app from their browser.

### Step 1: Make sure the stack is running

```powershell
docker compose up -d
Invoke-WebRequest http://localhost  # should return HTML
```

### Step 2: Start the tunnel

Open a **separate PowerShell window** and run:

```powershell
cloudflared tunnel --url http://localhost
```

Look in the output for a line like:

```
+--------------------------------------------------------------------------+
| Your quick Tunnel has been created! Visit it at (it may take some time):|
|  https://random-words-something.trycloudflare.com                       |
+--------------------------------------------------------------------------+
```

**Copy that URL** — send it to whoever you want. They open it in any browser, anywhere on Earth.

### Stopping the tunnel

In the tunnel's PowerShell window, press `Ctrl+C`. The URL stops working immediately.

### Caveats

- The URL is **random each time** you start cloudflared. For a stable URL: create a free Cloudflare account + named tunnel (~10 min more setup — tell me when you want to do this).
- Your laptop + Docker must stay on. If the laptop sleeps, the URL stops working.

---

## Mode 3: APK for a phone

### Option A — Phone on your home Wi-Fi (no tunnel needed)

#### A1. Find your laptop's local IP

```powershell
ipconfig | findstr "IPv4"
```

Look for an entry like `IPv4 Address. . . . . . . . . . . : 192.168.1.42`. That's your laptop's IP on your home network.

#### A2. Open Windows Firewall for port 8000

Run **as Administrator** (right-click PowerShell → "Run as administrator"):

```powershell
New-NetFirewallRule -DisplayName "Eldercare Backend" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
```

(Only needed once per PC.)

#### A3. Build the APK with your laptop's IP

```powershell
.\build_apk.ps1 -Url "http://192.168.1.42:8000"
```

Replace `192.168.1.42` with whatever `ipconfig` showed.

Result: `eldercare.apk` at the project root (~50 MB).

#### A4. Install on your phone

Send `eldercare.apk` to your phone (WhatsApp/email/Drive/USB), tap it, allow "Install unknown apps" for whichever app you used to receive it, install.

The phone must be on the **same Wi-Fi as your laptop** for the app to reach the backend.

### Option B — Phone anywhere on Earth (uses tunnel)

#### B1. Backend up

```powershell
docker compose up -d
```

#### B2. Start a tunnel (separate PowerShell window — keep it open)

```powershell
cloudflared tunnel --url http://localhost:8000
```

Note the URL (e.g. `https://florist-foo.trycloudflare.com`).

#### B3. Build APK with the tunnel URL

```powershell
.\build_apk.ps1 -Url "https://florist-foo.trycloudflare.com"
```

#### B4. Distribute

Send `eldercare.apk` to anyone. They install + use it. Works from anywhere as long as your laptop + tunnel are running.

---

## Mode 4: Mobile dev with hot reload (no APK rebuild)

### Option A — Real phone via USB cable

#### One-time phone setup

1. On Android: **Settings → About phone** → tap **Build number** seven times. ("Developer mode enabled.")
2. **Settings → System → Developer options** → enable **USB debugging**
3. Plug phone into laptop with a USB-C/Lightning cable
4. On phone: tap **Allow** when "Allow USB debugging?" pops up

#### Verify it's detected

```powershell
flutter devices
# Should list your phone by name (e.g. "Samsung S22 (mobile)")
```

#### Run

```powershell
.\dev.ps1 phone
```

App installs + launches on the phone. Edit any `.dart` file → save → changes appear on the phone in ~1 second.

### Option B — Android emulator

1. Open **Android Studio** → **Device Manager** (right side panel) → **Create Virtual Device**
2. Pick **Pixel 7** (or any phone), **API 34** (Android 14)
3. Click the play ▶ arrow next to the emulator name — wait ~30 sec for it to boot
4. ```powershell
   .\dev.ps1 emulator
   ```

---

## Stopping everything cleanly

```powershell
# Stop Docker stack
docker compose down

# Stop the tunnel: Ctrl+C in the cloudflared window
# Stop `flutter run`: press 'q' in its terminal
```

`docker compose down` does NOT delete your database — it persists in a Docker volume. Next `docker compose up -d` brings it back instantly.

If you want a clean nuke (forgetting all data):

```powershell
docker compose down -v
```

---

## Common errors and fixes

| Error you see | What's wrong | Fix |
|---|---|---|
| "Connection refused" / "Sign-in failed" in app | Backend isn't running | `docker compose up -d backend` |
| Web app blank in browser | Frontend container down | `docker compose up -d frontend` then open `http://localhost` |
| `docker compose` says "daemon not running" | Docker Desktop closed | Start Docker Desktop, wait for whale icon to stop animating |
| Login screen but says "missing bearer token" everywhere | APK was built before auth fix | Rebuild with `.\build_apk.ps1 -Url ...` |
| APK opens but every screen says network error | URL baked into APK no longer reachable (tunnel died, IP changed) | Rebuild APK with the current URL |
| "No devices" when running `flutter run` | Phone disconnected / USB debugging off | `flutter devices` to verify, replug cable |
| Cloudflare tunnel URL doesn't load | Tunnel window got closed | Restart it: `cloudflared tunnel --url http://localhost` |
| Hot reload not picking up changes | File not saved | Ctrl+S in your editor; if still nothing, press `R` (capital) for hot restart |
| Build fails with "Dart SDK version" | Pubspec was edited | `flutter pub get` then retry |

---

## File reference

| File | Purpose |
|---|---|
| **`dev.ps1`** | Run app in dev mode with hot reload (Chrome / phone / emulator) |
| **`build_apk.ps1`** | Build a release APK for Android |
| **`docker-compose.yml`** | Defines all services: backend, db, redis, ml_manager, frontend (web) |
| **`.env`** | Backend secrets and config (not in git) |
| **`frontend/`** | Flutter codebase — same source for web + mobile |
| **`backend/`** | Python FastAPI backend |
| **`ml_manager/`** | ML pipeline orchestrator |
| **`eldercare.apk`** | Last-built APK, ready to share |
| **`FIREBASE_SETUP.md`** | How to enable push notifications |

---

## Environment variables (advanced)

You usually don't need to touch these — the scripts handle them.

| Variable | Where it lives | Default | What it does |
|---|---|---|---|
| `API_BASE_URL` | `--dart-define` at Flutter build | `http://localhost:8000` | REST API URL the app calls |
| `WS_BASE_URL` | `--dart-define` at Flutter build | `ws://localhost:8000` | WebSocket URL the app uses |
| `CORS_ORIGINS` | `.env` | `http://localhost:3000,...:8080,...:80,localhost` | Which web origins backend will respond to |
| `BACKEND_PORT` | `.env` | `8000` | Host port the backend container binds |
| `FRONTEND_PORT` | `.env` | `80` | Host port the web frontend container binds |

---

## Three concrete scenarios

### Scenario 1: "Just turned my PC on, want to keep coding the web app"

```powershell
# Wait for Docker Desktop to finish starting (whale icon stable)
cd c:\Users\PC\Documents\GitHub\FYP
docker compose up -d              # backend + db + redis + ml + frontend
.\dev.ps1                          # opens Chrome, hot reload on
```

Edit code, save, see changes. Done.

### Scenario 2: "Want to test on my own phone right now"

```powershell
# Backend stack
docker compose up -d

# Find your IP
ipconfig | findstr "IPv4"        # → e.g. 192.168.1.42

# Build APK
.\build_apk.ps1 -Url "http://192.168.1.42:8000"

# Send eldercare.apk to phone, install, log in. Done.
```

### Scenario 3: "Want a friend in another city to test the app"

```powershell
# Backend stack
docker compose up -d

# Tunnel — leave this window running
cloudflared tunnel --url http://localhost:8000
# Copy the https://...trycloudflare.com URL

# In another PowerShell, build APK
.\build_apk.ps1 -Url "https://your-tunnel-url.trycloudflare.com"

# WhatsApp eldercare.apk to your friend. They install, log in, done.
# Your laptop must stay on.
```

---

## Sanity check before showing to anyone

Quick 30-second smoke test that everything works end-to-end:

```powershell
# 1. Backend
Invoke-WebRequest http://localhost:8000/health
# Expect: {"status":"ok",...}

# 2. Web frontend
Invoke-WebRequest http://localhost
# Expect: HTML starting with <!DOCTYPE html>

# 3. Login round-trip
$body = @{ email = "admin@eldercare.local"; password = "Admin@12345" } | ConvertTo-Json
Invoke-WebRequest http://localhost:8000/api/auth/login -Method Post -Body $body -ContentType "application/json"
# Expect: 200 OK with an access_token in the response body
```

If all three pass, the system is healthy.
