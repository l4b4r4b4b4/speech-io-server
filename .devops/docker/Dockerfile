# Multi-stage build for speech-io-server

# Stage 1: Builder stage for dependencies
ARG CUDA_VARIANT=devel
FROM nvidia/cuda:12.8.1-${CUDA_VARIANT}-ubuntu22.04 as builder

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies needed for building
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    build-essential \
    git \
    ninja-build \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime stage
ARG CUDA_VARIANT=devel
FROM nvidia/cuda:12.8.1-${CUDA_VARIANT}-ubuntu22.04

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.local/bin:$PATH"

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    libsndfile1 \
    ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy Python dependencies from builder stage
COPY --from=builder /root/.local /root/.local

# Copy application code
COPY . .

# Create required directories
RUN mkdir -p model_cache reference_audio outputs voices

# Expose the port the application will run on (default to 8003 as per config)
EXPOSE 8003

# Command to run the application
CMD ["python3", "server.py"]
