#!/bin/bash

# Quick Docker Start Script - No Waiting, Just Build
# This script bypasses the wait loop and starts building immediately

set -e

echo "============================================"
echo "Quick Docker Build - JAIS2 Variant"
echo "============================================"

# Configuration
REGISTRY="${DOCKER_REGISTRY:-nikolasth90/}"
IMAGE_NAME="${IMAGE_NAME:-vllm-universal}"
TAG="${TAG:-latest}"
VARIANT="jais2"

# Full image name
FULL_IMAGE_NAME="${REGISTRY}${IMAGE_NAME}:${VARIANT}-${TAG}"

echo "🔧 Configuration:"
echo "  • Image: $FULL_IMAGE_NAME"
echo "  • Dockerfile: Dockerfile-jais2"
echo ""

# Check if Docker is available, install if needed
if ! command -v docker >/dev/null 2>&1; then
    echo "📦 Docker not found. Installing..."
    if [ -f "./install-docker-container.sh" ]; then
        sudo ./install-docker-container.sh
    else
        echo "❌ ERROR: install-docker-container.sh not found"
        exit 1
    fi
fi

# Start Docker daemon if in container (no waiting loop)
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    echo "🐳 Container environment detected. Starting Docker daemon..."
    
    # Create directories
    sudo mkdir -p /var/run /var/lib/docker
    
    # Kill any existing Docker daemon
    sudo pkill dockerd 2>/dev/null || true
    sleep 2
    
    # Start Docker daemon immediately
    sudo dockerd \
        --host=unix:///var/run/docker.sock \
        --host=tcp://0.0.0.0:2375 \
        --tls=false \
        --tlsverify=false \
        --storage-driver=overlay2 \
        --data-root=/var/lib/docker \
        --iptables=false \
        --ip-masq=false \
        --bridge=none \
        --log-level=warn > /tmp/dockerd.log 2>&1 &
    
    echo "🚀 Docker daemon started. Waiting briefly for socket..."
    
    # Wait specifically for the socket to be created
    for i in {1..10}; do
        if [ -S /var/run/docker.sock ]; then
            echo "✅ Docker socket created!"
            break
        fi
        echo "⏳ Waiting for Docker socket... ($i/10)"
        sleep 1
    done
    
    # Test Docker connection
    echo "🔍 Testing Docker connection..."
    for i in {1..20}; do
        if sudo docker version >/dev/null 2>&1; then
            echo "✅ Docker is ready!"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "⚠️  Docker taking longer than expected..."
        fi
        sleep 1
    done
    
    # Set DOCKER_HOST for the build
    export DOCKER_HOST="unix:///var/run/docker.sock"
else
    echo "🖥️  Standard system detected."
fi

# Enable BuildKit
export DOCKER_BUILDKIT=1
export BUILDKIT_STEP_LOG_MAX_SIZE=10000000

echo ""
echo "🔨 Building $VARIANT variant..."
echo "📦 Image: $FULL_IMAGE_NAME"
echo ""

# Build immediately without waiting loop
echo "🔨 Starting build command..."
if [ "$EUID" -eq 0 ] || [ -f /.dockerenv ]; then
    # Run as root or in container
    sudo docker build \
        --file "Dockerfile-jais2" \
        --tag "$FULL_IMAGE_NAME" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --progress=plain \
        .
else
    # Run as regular user
    docker build \
        --file "Dockerfile-jais2" \
        --tag "$FULL_IMAGE_NAME" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --progress=plain \
        .
fi

echo ""
echo "✅ Build completed: $FULL_IMAGE_NAME"

# Show image info
echo ""
echo "📊 Image Information:"
sudo docker images "$FULL_IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

# Push if registry is configured
if [[ "$FULL_IMAGE_NAME" == */* ]]; then
    echo ""
    echo "🚀 Pushing to registry..."
    sudo docker push "$FULL_IMAGE_NAME"
    echo "✅ Push completed: $FULL_IMAGE_NAME"
else
    echo ""
    echo "ℹ️  Local build complete. No registry push configured."
fi

echo ""
echo "=========================================="
echo "✅ Quick Build Complete!"
echo "=========================================="
echo ""
echo "🎯 Ready to use:"
echo "  docker run -p 8000:8000 $FULL_IMAGE_NAME"

# If in container, show Docker daemon logs
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    echo ""
    echo "📋 Docker daemon logs: /tmp/dockerd.log"
    echo "   (Check with: tail -f /tmp/dockerd.log)"
fi