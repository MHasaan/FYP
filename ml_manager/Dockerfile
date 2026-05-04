# syntax=docker/dockerfile:1
# ============================================
# ML Manager - NVIDIA CUDA Base Image
# ============================================
# Uses CUDA 11.8 runtime for GPU access
# Includes Python 3.11, OpenCV, PyTorch, ultralytics

FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

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
    curl

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Upgrade pip (cached)
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip

# Install Python dependencies (cached — PyTorch ~2GB stays in cache between rebuilds)
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 300 --retries 5 -r requirements.txt

# Fix onnxruntime conflict: remove CPU version, ensure GPU version is installed
# Separate layer so it only reruns when requirements.txt changes
RUN --mount=type=cache,target=/root/.cache/pip \
    pip uninstall -y onnxruntime 2>/dev/null; \
    pip install --timeout 300 --retries 5 onnxruntime-gpu==1.17.1

# Copy model weights first (changes rarely — stays cached when code changes)
COPY models/ ./models/

# Copy application code last (changes frequently — only this layer rebuilds)
COPY manager/ ./manager/
COPY steps/ ./steps/

# Expose port for health checks
EXPOSE 8001

# Run the ML Manager
CMD ["python", "-m", "manager.main"]
