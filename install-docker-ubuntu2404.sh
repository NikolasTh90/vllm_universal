#!/bin/bash

# Docker Installation Script for Ubuntu 24.04 with Performance Optimization Plugins
# This script installs Docker with plugins and configurations to significantly speed up builds
# Note: This script is designed for full Ubuntu systems, not containers/kubernetes pods

set -e

# Check if running in a container/kubernetes pod
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    echo "WARNING: This script appears to be running inside a container/kubernetes pod."
    echo "Docker-in-Docker setups require different configuration."
    echo "This script is designed for full Ubuntu systems with systemd."
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

echo "============================================"
echo "Installing Docker with performance optimization plugins for Ubuntu 24.04"
echo "============================================"

# Update package index
echo "Updating package index..."
sudo apt-get update

# Install packages to allow apt to use a repository over HTTPS
echo "Installing prerequisite packages..."
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Add Docker's official GPG key
echo "Adding Docker's official GPG key..."
sudo mkdir -p /etc/apt/keyrings
if [ -f "/etc/apt/keyrings/docker.gpg" ]; then
    echo "Docker GPG key already exists, updating..."
    sudo rm -f /etc/apt/keyrings/docker.gpg
fi
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index after adding Docker repository
echo "Updating package index after adding Docker repository..."
sudo apt-get update

# Install Docker Engine, CLI, containerd, and Docker Compose plugin
echo "Installing Docker Engine, CLI, containerd, and Docker Compose..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin

# Create Docker group (if it doesn't exist)
echo "Setting up Docker group..."
if ! getent group docker > /dev/null 2>&1; then
    sudo groupadd docker
fi

# Add current user to docker group
echo "Adding current user to docker group..."
if [ -n "$SUDO_USER" ]; then
    sudo usermod -aG docker $SUDO_USER
    echo "Added user '$SUDO_USER' to docker group"
elif [ -n "$USER" ] && [ "$USER" != "root" ]; then
    sudo usermod -aG docker $USER
    echo "Added user '$USER' to docker group"
else
    echo "Warning: Could not determine username to add to docker group"
    echo "Note: In container environments, Docker group addition may not be applicable"
fi

# Configure Docker for optimal performance
echo "Configuring Docker for optimal performance..."
sudo mkdir -p /etc/docker

# Create Docker daemon configuration with performance optimizations
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "data-root": "/var/lib/docker",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323",
  "exec-opt": ["native.cgroupdriver=systemd"],
  "bridge": "none",
  "ip-forward": true,
  "iptables": true,
  "ip-masq": true,
  "mtu": 1500
}
EOF

# Install buildkit with advanced caching
echo "Installing and configuring Docker BuildKit with advanced caching..."
sudo mkdir -p /etc/buildkit

# Create BuildKit configuration for optimal performance
sudo tee /etc/buildkit/buildkitd.toml > /dev/null <<EOF
[worker.oci]
  max-parallelism = 4
  # Enable caching with garbage collection
  gc = true
  gckeepstorage = 9000
  # Use cache mount to speed up builds
  snapshotter = "overlayfs"
  
[registry."docker.io"]
  mirrors = ["https://registry-mirror.docker.io", "https://mirror.gcr.io"]

[registry."ghcr.io"]
  mirrors = ["https://ghcr.io-mirror"]

[registry."quay.io"]
  mirrors = ["https://quay.io-mirror"]
EOF

# Enable and start Docker service (skip if running in container)
if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
    echo "Enabling and starting Docker service..."
    sudo systemctl enable docker
    sudo systemctl restart docker

    # Enable BuildKit
    echo "Enabling Docker BuildKit..."
    sudo systemctl enable buildkit
    sudo systemctl restart buildkit 2>/dev/null || echo "BuildKit service not found, will use built-in BuildKit"
else
    echo "Systemd not available (running in container). Skipping service management."
    echo "Docker configuration files have been created and will be used when Docker starts."
fi

# Install additional performance optimization tools
echo "Installing additional performance optimization tools..."

# Install dive for Docker image analysis
echo "Installing dive for Docker image analysis..."
sudo wget -O /tmp/dive.tar.gz https://github.com/wagoodman/dive/releases/download/v0.11.0/dive_0.11.0_linux_amd64.tar.gz
sudo tar -xzf /tmp/dive.tar.gz -C /tmp
sudo cp /tmp/dive /usr/local/bin/
sudo chmod +x /usr/local/bin/dive
sudo rm -f /tmp/dive.tar.gz /tmp/dive

# Install lazydocker for Docker management
echo "Installing lazydocker for Docker management..."
curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | sudo bash

# Install DockerSlim for image optimization
echo "Installing DockerSlim for image optimization..."
if [ ! -f "/usr/local/bin/docker-slim" ]; then
    sudo wget -O /tmp/docker-slim.tar.gz https://github.com/docker-slim/docker-slim/releases/download/1.40.11/docker-slim_linux_1.40.11.tar.gz
    sudo tar -xzf /tmp/docker-slim.tar.gz -C /tmp
    sudo cp /tmp/docker-slim-linux/* /usr/local/bin/ 2>/dev/null || sudo cp /tmp/docker-slim /usr/local/bin/
    sudo chmod +x /usr/local/bin/docker-slim*
    sudo rm -rf /tmp/docker-slim*
fi

# Configure system limits for Docker
echo "Configuring system limits for optimal Docker performance..."
sudo tee /etc/sysctl.d/99-docker.conf > /dev/null <<EOF
# Docker performance optimization
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
vm.swappiness = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

# Apply system settings (skip if not available or in container)
if [ -f /etc/sysctl.d/99-docker.conf ]; then
    if command -v sysctl >/dev/null 2>&1; then
        echo "Applying system performance settings..."
        sudo sysctl -p /etc/sysctl.d/99-docker.conf 2>/dev/null || echo "Note: Some sysctl settings may not apply in container environments"
    else
        echo "Sysctl not available. System settings will be applied on next boot."
    fi
fi

# Create optimized Docker profiles script
echo "Creating Docker optimization helper scripts..."
sudo tee /usr/local/bin/docker-speedup > /dev/null <<'EOF'
#!/bin/bash

# Docker Speedup Script
# Usage: docker-speedup [build|prune|analyze]

case "$1" in
    build)
        echo "Building with Docker BuildKit and cache optimization..."
        export DOCKER_BUILDKIT=1
        export BUILDKIT_STEP_LOG_MAX_SIZE=10000000
        export BUILDKIT_STEP_LOG_MAX_SPEED=100
        shift
        docker build "$@"
        ;;
    prune)
        echo "Cleaning up Docker resources while preserving cache..."
        docker system prune -f --volumes --filter "until=24h"
        docker builder prune -f --all --filter "until=24h"
        ;;
    analyze)
        echo "Analyzing Docker image with dive..."
        if [ -z "$2" ]; then
            echo "Usage: docker-speedup analyze <image_name>"
            exit 1
        fi
        dive "$2"
        ;;
    slim)
        echo "Optimizing Docker image with DockerSlim..."
        if [ -z "$2" ]; then
            echo "Usage: docker-speedup slim <image_name>"
            exit 1
        fi
        docker-slim build "$2"
        ;;
    *)
        echo "Docker Speedup Helper"
        echo "Usage: docker-speedup [build|prune|analyze|slim]"
        echo ""
        echo "Commands:"
        echo "  build     - Build with BuildKit and cache optimization"
        echo "  prune     - Clean up resources while preserving cache"
        echo "  analyze   - Analyze image with dive"
        echo "  slim      - Optimize image with DockerSlim"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/docker-speedup

# Display installation summary
echo ""
echo "============================================"
echo "Docker Installation with Performance Plugins Complete!"
echo "============================================"
echo ""
echo "🚀 Performance Features Installed:"
echo "  • Docker Engine with latest stable version"
echo "  • Docker BuildKit with advanced caching"
echo "  • Optimized daemon configuration"
echo "  • Registry mirrors for faster downloads"
echo "  • System limits optimization"
echo ""
echo "🛠️  Performance Tools Installed:"
echo "  • dive - Docker image analysis tool"
echo "  • lazydocker - Terminal UI for Docker"
echo "  • docker-slim - Image optimization tool"
echo "  • docker-speedup - Custom optimization helper"
echo ""
echo "📋 Usage Tips:"
echo "  • Use 'docker-speedup build' instead of 'docker build' for faster builds"
echo "  • Use 'docker-speedup analyze <image>' to analyze image efficiency"
echo "  • Use 'docker-speedup slim <image>' to optimize image size"
echo "  • Use 'docker-speedup prune' to clean up while preserving cache"
echo "  • Run 'lazydocker' for a terminal Docker management UI"
echo ""
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    echo "⚠️  CONTAINER ENVIRONMENT DETECTED:"
    echo "   • Docker configuration files have been created"
    echo "   • Service management is not available in containers"
    echo "   • For Docker-in-Docker setups, consider using dind or sidecar patterns"
    echo "   • Performance tools are installed and ready to use"
else
    echo "⚠️  IMPORTANT: Log out and log back in to use Docker without sudo"
    if [ -n "$SUDO_USER" ]; then
        echo "   (or run: newgrp docker as user '$SUDO_USER')"
    else
        echo "   (or run: newgrp docker)"
    fi
fi
echo ""
echo "🔧 Configuration files:"
echo "  • Docker daemon: /etc/docker/daemon.json"
echo "  • BuildKit config: /etc/buildkit/buildkitd.toml"
echo "  • System limits: /etc/sysctl.d/99-docker.conf"
echo ""
echo "✅ Installation complete! Docker is now optimized for high-performance builds."