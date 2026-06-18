# syntax=docker/dockerfile:1
# ============================================
# ML Manager - NVIDIA CUDA Base Image
# ============================================
# Uses CUDA 11.8 *devel* for GPU access AND nvcc.
# nvcc is required to compile GroundingDINO's MultiScaleDeformableAttention
# custom CUDA op (see GroundingDINO/groundingdino/models/GroundingDINO/csrc).
# The devel image is ~3GB bigger than runtime — accepted cost.
# Build context: repo root (set in docker-compose.yml).

FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
# Force unbuffered Python output for Docker logs
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies (cached across rebuilds — saves ~200MB re-download)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3-pip \
    python3.11-dev \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    ffmpeg \
    curl \
    git \
    build-essential

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Upgrade pip (cached)
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip

# Install Python dependencies (cached — PyTorch ~2GB stays in cache between rebuilds)
COPY ml_manager/requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 300 --retries 5 -r requirements.txt

# Force-reinstall onnxruntime-gpu cleanly: previous installs sometimes left
# the package dir half-populated (missing __init__.py), making `import
# onnxruntime` succeed as an empty namespace package and breaking all
# .get_available_providers() callers downstream. The smoke-test at the
# end fails the build if the install is still broken.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip uninstall -y onnxruntime onnxruntime-gpu 2>/dev/null; true && \
    pip install --force-reinstall --no-deps --timeout 300 --retries 5 onnxruntime-gpu==1.17.1 && \
    python -c "import onnxruntime; assert onnxruntime.get_available_providers(), 'onnxruntime install broken — no providers'"

# Pin transformers to 4.x BEFORE installing GroundingDINO. GroundingDINO's
# setup.py lists `transformers` without a version pin, so on a clean install
# pip resolves to the latest (5.x) which requires torch>=2.5 — incompatible
# with our pinned torch==2.4.1 (cu118). With this preinstalled, pip's resolver
# is satisfied and won't upgrade to 5.x when GroundingDINO is installed.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 300 --retries 5 "transformers>=4.45.0,<5.0.0"

# Install GroundingDINO. The source ships its own setup.py that compiles
# the custom CUDA op MultiScaleDeformableAttention at install time.
#
# TORCH_CUDA_ARCH_LIST controls which GPU architectures the custom op is
# compiled for. The default below covers every common NVIDIA consumer/
# datacenter GPU from Volta (V100) through Hopper (H100), plus PTX for
# forward-compat with future arches. This makes the resulting image
# portable across machines — at the cost of a longer compile.
#
# Compute capabilities cheatsheet:
#   7.0  V100
#   7.5  T4, RTX 2060/2070/2080 (incl. SUPER variants)
#   8.0  A100
#   8.6  RTX 3060/3070/3080/3090
#   8.9  RTX 4060/4070/4080/4090
#   9.0  H100
#
# To shrink build time on a single-GPU machine, override at build time:
#   docker compose build --build-arg TORCH_CUDA_ARCH_LIST="7.5" ml_manager
ARG TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0+PTX"
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}
ENV CUDA_HOME=/usr/local/cuda

# GroundingDINO source now lives in-repo (absorbed into the build context at
# the repo root). COPY it instead of cloning from GitHub:
#   - No network fetch on every build — fully offline/deterministic.
#   - Cached as a normal layer keyed on the source file contents, which rarely
#     change, so the expensive CUDA-op compile below stays cached across rebuilds.
# (Previously this `git clone`d IDEA-Research/GroundingDINO@856dde2 at build
# time, which re-downloaded each time its layer cache was invalidated.)
COPY GroundingDINO/ ./GroundingDINO/

# --no-build-isolation: GroundingDINO's setup.py imports torch at build time.
# PEP 517 build isolation hides our installed torch from the build venv,
# and setup.py then naively runs `pip install torch` (no cu118 index) which
# pulls cu130 wheels and breaks the CUDA-op link. Building without isolation
# means setup.py sees the cu118 torch we already installed.
# Pre-install build deps (setuptools, wheel, ninja) in the parent env since
# --no-build-isolation skips that step.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 3 setuptools wheel ninja && \
    pip install --timeout 600 --retries 3 --no-build-isolation ./GroundingDINO && \
    python -c "import groundingdino; from groundingdino.models import build_model; print('GroundingDINO OK')"

# Copy model weights first (changes rarely — stays cached when code changes).
# Includes groundingdino_swint_ogc.pth (~700MB) — see README for download URL.
COPY ml_manager/models/ ./models/

# Copy application code last (changes frequently — only this layer rebuilds)
COPY ml_manager/manager/ ./manager/
COPY ml_manager/steps/ ./steps/

# Expose port for health checks
EXPOSE 8001

# Run the ML Manager
CMD ["python", "-m", "manager.main"]
