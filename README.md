# Eldercare — Patient Monitoring & Surveillance System

FYP project. Five-service Dockerized stack: PostgreSQL 16, Redis 7, FastAPI
backend, GPU-accelerated ML manager (RTMPose + EnhancedVSViG fall detection +
GroundingDINO object detection), and Flutter app (web + Android).

---

## Quickstart on a fresh PC

### 1. Prerequisites

You need an **NVIDIA GPU**. The `ml_manager` service compiles a custom
CUDA op at build time and runs GPU-only inference at runtime — there is
no CPU-only fallback path.

| Component | Minimum version |
| --- | --- |
| NVIDIA driver | 525.x (CUDA 12.x compatible) |
| Docker Engine / Docker Desktop | 24.x with Compose v2 |
| Linux only: `nvidia-container-toolkit` | latest from NVIDIA's apt repo |
| Git LFS | latest (the ~660 MB GroundingDINO weights live in LFS) |
| For Android APK build (optional): Flutter SDK | 3.24+ |

**Windows:** Docker Desktop's WSL2 backend handles NVIDIA passthrough
automatically once the host driver is installed. No extra toolkit needed.

**Linux:** install nvidia-container-toolkit per
[NVIDIA's docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html),
then restart Docker.

### 2. Clone and fetch LFS

```powershell
git lfs install                        # one-time per machine
git clone https://github.com/MHasaan/FYP.git
cd FYP
git lfs pull                           # downloads ~700 MB of model weights
```

If `git lfs pull` is skipped, `ml_manager/models/groundingdino_swint_ogc.pth`
will be a 134-byte pointer file and the build will fail on the
`COPY ml_manager/models/` step.

### 3. Bring the stack up

```powershell
docker compose up -d --build
```

First build takes **15–30 minutes** because the `ml_manager` image compiles
GroundingDINO's `MultiScaleDeformableAttention` CUDA op for every common
GPU architecture (7.0 through 9.0). Subsequent builds reuse the layer cache
and finish in under a minute.

To shrink the first build on a single-GPU machine, set
`TORCH_CUDA_ARCH_LIST` to just your GPU's compute capability:

```powershell
# example: RTX 30-series only
$env:TORCH_CUDA_ARCH_LIST = "8.6"
docker compose up -d --build
```

| Your GPU | Compute capability |
| --- | --- |
| RTX 2060 / 2070 / 2080 (SUPER) | 7.5 |
| RTX 3060 / 3070 / 3080 / 3090 | 8.6 |
| RTX 4060 / 4070 / 4080 / 4090 | 8.9 |
| A100 | 8.0 |
| H100 | 9.0 |

### 4. Verify GPU is actually being used

```powershell
docker compose exec ml_manager python -m manager.check_gpu
```

Expected output (truncated):

```
Torch CUDA available: True
Torch CUDA device name: NVIDIA GeForce RTX ...
ONNX Runtime available providers: ['CUDAExecutionProvider', 'CPUExecutionProvider']
```

If `CUDA available: False` or `CUDAExecutionProvider` is missing, GPU
passthrough is broken — re-check driver + nvidia-container-toolkit.

### 5. Open the apps

- Web: <http://localhost>
- Backend API docs: <http://localhost:8000/docs>
- ML manager health: <http://localhost:8001/health>

Default admin login is seeded by `database/init.sql` — see that file
for credentials.

---

## Optional: one-shot dev start with public tunnels + APK

`OneShotRun.ps1` brings the stack up, starts two Cloudflare quick
tunnels (web + backend), and builds an Android APK with the backend
tunnel URL baked in. Useful for demoing on a phone over the internet.

```powershell
.\OneShotRun.ps1                # everything
.\OneShotRun.ps1 -SkipApk       # skip the APK build
.\OneShotRun.ps1 -LocalOnly     # no tunnels, APK targets LAN IP
```

Requires `cloudflared.exe` on PATH for the tunnel modes. Read the
script header for details.

---

## Service map

| Service | Port | What it does |
| --- | --- | --- |
| `database` | 5432 | PostgreSQL 16 — users, patients, cameras, incidents, jobs |
| `redis` | 6379 | Pub/sub message bus between backend and ml_manager |
| `backend` | 8000 | FastAPI REST + WebSocket; ~20 route modules |
| `ml_manager` | 8001 | GPU pipeline: RTMPose → EnhancedVSViG fall detection; GroundingDINO object detection |
| `frontend` | 80 | Flutter web bundle served by Nginx |

Only `ml_manager` needs the GPU.

---

## Troubleshooting

**Build fails at `git clone GroundingDINO`** — you're offline or behind
a proxy that blocks GitHub. Pre-clone into `./GroundingDINO/` and edit
the Dockerfile back to `COPY GroundingDINO/ ./GroundingDINO/`.

**`MultiScaleDeformableAttention` ImportError at runtime** — the custom
CUDA op was compiled for a different arch than your GPU. Rebuild with
`TORCH_CUDA_ARCH_LIST` matching your card (see table above).

**Model file is 134 bytes, not 660 MB** — you cloned without LFS. Run
`git lfs install && git lfs pull`.

**`onnxruntime` has no providers** — the build-time smoke test should
have caught this. Force a full rebuild with
`docker compose build --no-cache ml_manager`.

**GPU not visible inside the container** — on Linux, confirm
`nvidia-container-toolkit` is installed and Docker daemon was restarted
after install. On Windows, make sure Docker Desktop is using the WSL2
backend (Settings → General).
