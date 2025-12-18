#!/bin/bash

# Docker Installation Script for Container/Kubernetes Environments
# This script configures Docker for optimal performance in containerized environments
# Designed for when Docker needs to run inside containers (Docker-in-Docker)

set -e

echo "============================================"
echo "Configuring Docker for Container/Kubernetes Environment"
echo "============================================"

# Check if running in a container/kubernetes pod
if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ -z "$KUBERNETES_SERVICE_HOST" ]; then
    echo "WARNING: This script is designed for container environments."
    echo "It seems you're running on a full system."
    echo "Consider using install-docker-ubuntu2404.sh instead."
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Install basic dependencies that might be missing
echo "Installing basic dependencies..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        curl \
        wget \
        tar \
        ca-certificates \
        gnupg \
        jq
fi

# Create Docker configuration directories
echo "Setting up Docker configuration..."
sudo mkdir -p /etc/docker
sudo mkdir -p /etc/buildkit

# Create Docker daemon configuration optimized for containers
echo "Creating Docker daemon configuration for containers..."
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "data-root": "/var/lib/docker",
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "bridge": "docker0",
  "ip-forward": true,
  "iptables": false,
  "ip-masq": false,
  "mtu": 1500,
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc"
    }
  }
}
EOF

# Create BuildKit configuration for containers
echo "Creating BuildKit configuration for containers..."
sudo tee /etc/buildkit/buildkitd.toml > /dev/null <<'EOF'
[worker.oci]
  max-parallelism = 2
  gc = true
  gckeepstorage = 1000
  snapshotter = "overlayfs"
  rootless = true

[worker.oci.labels]
  "org.mobyproject.buildkit.worker.oci" = "container"

[registry."docker.io"]
  mirrors = ["https://registry-mirror.docker.io"]

[registry."ghcr.io"]
  mirrors = ["https://ghcr.io-mirror"]

[registry."quay.io"]
  mirrors = ["https://quay.io-mirror"]
EOF

# Install performance tools that work in containers
echo "Installing performance optimization tools..."

# Install dive for Docker image analysis
if ! command -v dive >/dev/null 2>&1; then
    echo "Installing dive for Docker image analysis..."
    sudo wget -O /tmp/dive.tar.gz https://github.com/wagoodman/dive/releases/download/v0.11.0/dive_0.11.0_linux_amd64.tar.gz
    sudo tar -xzf /tmp/dive.tar.gz -C /tmp
    sudo cp /tmp/dive /usr/local/bin/
    sudo chmod +x /usr/local/bin/dive
    sudo rm -f /tmp/dive.tar.gz /tmp/dive
fi

# Install DockerSlim for image optimization
if ! command -v docker-slim >/dev/null 2>&1; then
    echo "Installing DockerSlim for image optimization..."
    sudo wget -O /tmp/docker-slim.tar.gz https://github.com/docker-slim/docker-slim/releases/download/1.40.11/docker-slim_linux_1.40.11.tar.gz
    sudo tar -xzf /tmp/docker-slim.tar.gz -C /tmp
    sudo cp /tmp/docker-slim-linux/* /usr/local/bin/ 2>/dev/null || sudo cp /tmp/docker-slim /usr/local/bin/
    sudo chmod +x /usr/local/bin/docker-slim*
    sudo rm -rf /tmp/docker-slim*
fi

# Create container-optimized helper script
echo "Creating container-optimized helper scripts..."
sudo tee /usr/local/bin/docker-container-speedup > /dev/null <<'EOF'
#!/bin/bash

# Docker Container Speedup Script
# Optimized for containerized environments (Docker-in-Docker)
# Usage: docker-container-speedup [build|prune|analyze|slim|start]

start_docker() {
    echo "Starting Docker daemon in container mode..."
    if [ ! -f /var/run/docker.pid ]; then
        # Create necessary directories
        sudo mkdir -p /var/run /var/lib/docker
        
        # Start Docker daemon with container-specific flags
        sudo dockerd \
            --host=unix:///var/run/docker.sock \
            --host=tcp://0.0.0.0:2375 \
            --storage-driver=overlay2 \
            --exec-root=/var/run/docker \
            --data-root=/var/lib/docker \
            --pidfile=/var/run/docker.pid \
            --iptables=false \
            --ip-masq=false \
            --bridge=none \
            --debug &
        
        # Wait for Docker to start
        echo "Waiting for Docker daemon to start..."
        for i in {1..30}; do
            if docker version >/dev/null 2>&1; then
                echo "Docker daemon started successfully!"
                return 0
            fi
            sleep 1
        done
        echo "Failed to start Docker daemon"
        return 1
    else
        echo "Docker daemon is already running"
    fi
}

build() {
    echo "Building with Docker BuildKit and cache optimization..."
    export DOCKER_BUILDKIT=1
    export BUILDKIT_STEP_LOG_MAX_SIZE=10000000
    export BUILDKIT_STEP_LOG_MAX_SPEED=100
    shift
    docker build "$@"
}

prune() {
    echo "Cleaning up Docker resources while preserving cache..."
    docker system prune -f --volumes --filter "until=24h"
    docker builder prune -f --all --filter "until=24h"
}

analyze() {
    echo "Analyzing Docker image with dive..."
    if [ -z "$2" ]; then
        echo "Usage: docker-container-speedup analyze <image_name>"
        exit 1
    fi
    dive "$2"
}

slim() {
    echo "Optimizing Docker image with DockerSlim..."
    if [ -z "$2" ]; then
        echo "Usage: docker-container-speedup slim <image_name>"
        exit 1
    fi
    docker-slim build "$2"
}

case "$1" in
    start)
        start_docker
        ;;
    build)
        build "$@"
        ;;
    prune)
        prune
        ;;
    analyze)
        analyze "$@"
        ;;
    slim)
        slim "$@"
        ;;
    *)
        echo "Docker Container Speedup Helper"
        echo "Usage: docker-container-speedup [start|build|prune|analyze|slim]"
        echo ""
        echo "Commands:"
        echo "  start     - Start Docker daemon in container mode"
        echo "  build     - Build with BuildKit and cache optimization"
        echo "  prune     - Clean up resources while preserving cache"
        echo "  analyze   - Analyze image with dive"
        echo "  slim      - Optimize image with DockerSlim"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/docker-container-speedup

# Create container startup script
echo "Creating Docker startup script for containers..."
sudo tee /usr/local/bin/start-docker-in-container > /dev/null <<'EOF'
#!/bin/bash

# Docker-in-Docker startup script
# This script starts Docker daemon optimized for container environments

echo "Starting Docker-in-Docker..."

# Create necessary directories
mkdir -p /var/run /var/lib/docker /tmp/docker

# Set permissions
chmod 755 /var/run /var/lib/docker /tmp/docker

# Start Docker daemon with container optimizations
dockerd \
    --host=unix:///var/run/docker.sock \
    --host=tcp://0.0.0.0:2375 \
    --storage-driver=overlay2 \
    --exec-root=/var/run/docker \
    --data-root=/var/lib/docker \
    --pidfile=/var/run/docker.pid \
    --iptables=false \
    --ip-masq=false \
    --bridge=none \
    --log-level=info \
    --userland-proxy=false \
    --live-restore &

# Wait for Docker to be ready
echo "Waiting for Docker daemon to be ready..."
while ! docker version >/dev/null 2>&1; do
    sleep 1
done

echo "Docker daemon is ready!"
echo "Socket: /var/run/docker.sock"
echo "TCP: tcp://0.0.0.0:2375"

# Keep the container running
if [ "$1" != "--no-keepalive" ]; then
    echo "Keeping container alive. Press Ctrl+C to stop."
    tail -f /dev/null
fi
EOF

sudo chmod +x /usr/local/bin/start-docker-in-container

# Display container-specific instructions
echo ""
echo "============================================"
echo "Docker Container Configuration Complete!"
echo "============================================"
echo ""
echo "🐳 Container Environment Detected:"
echo "  • Docker configuration files created"
echo "  • BuildKit configured for container use"
echo "  • Performance tools installed"
echo ""
echo "🚀 To start Docker in this container:"
echo "  • Command: start-docker-in-container"
echo "  • Or use: docker-container-speedup start"
echo ""
echo "🛠️  Performance Tools:"
echo "  • docker-container-speedup - Container-optimized helper"
echo "  • dive - Image analysis tool"
echo "  • docker-slim - Image optimization tool"
echo ""
echo "📋 Container Configuration:"
echo "  • Daemon config: /etc/docker/daemon.json"
echo "  • BuildKit config: /etc/buildkit/buildkitd.toml"
echo ""
echo "⚠️  Container Notes:"
echo "  • Use --privileged flag when running this container"
echo "  • Mount /var/lib/docker as volume for persistence"
echo "  • Expose port 2375 for TCP access if needed"
echo ""
echo "✅ Ready for Docker-in-Docker operations!"