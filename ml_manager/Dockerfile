# syntax=docker/dockerfile:1
# ============================================
# ML Manager - NVIDIA CUDA Base Image
# ============================================
# Uses CUDA 12.2 runtime for GPU access
# Includes Python 3.11, OpenCV, PyTorch, ultralytics

FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
# Force unbuffered Python output for Docker logs
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Upgrade pip
RUN python -m pip install --upgrade pip

# Install Python dependencies
COPY requirements.txt .
# 1. Install all requirements
# 2. Explicitly remove any onnxruntime (CPU) to avoid conflicts
# 3. Force reinstall onnxruntime-gpu to ensure a clean state
# 4. Remove any leftover __pycache__ or pyc files from the build context
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt && \
    pip uninstall -y onnxruntime onnxruntime-gpu && \
    pip install onnxruntime-gpu==1.17.1 && \
    find /app -name "__pycache__" -type d -exec rm -rf {} + && \
    find /app -name "*.pyc" -delete

# Copy application code
COPY manager/ ./manager/

# Copy pipeline step implementations
COPY steps/ ./steps/

# Copy model weights (if any)
COPY models/ ./models/

# Expose port for health checks
EXPOSE 8001

# Run the ML Manager
CMD ["python", "-m", "manager.main"]
