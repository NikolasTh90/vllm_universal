#!/bin/bash

# Buildah Installation Script for Container/Kubernetes Environments
# This script installs and configures buildah for containerized environments
# Designed for when buildah needs to run inside containers

set -e

echo "============================================"
echo "Installing Buildah for Container/Kubernetes Environment"
echo "============================================"

# Check if running in a container/kubernetes pod
if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ -z "$KUBERNETES_SERVICE_HOST" ]; then
    echo "WARNING: This script is designed for container environments."
    echo "It seems you're running on a full system."
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Install basic dependencies
echo "Installing basic dependencies..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        curl \
        wget \
        tar \
        ca-certificates \
        gnupg \
        software-properties-common \
        apt-transport-https \
        gnupg2 \
        pass
fi

# Install skopeo for registry operations
echo "Installing skopeo for registry operations..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y --no-install-recommends skopeo
else
    # Use binary installation if apt is not available
    SKOPEO_VERSION="v1.14.0"
    sudo wget -O /tmp/skopeo.tar.gz "https://github.com/containers/skopeo/releases/download/${SKOPEO_VERSION}/skopeo-${SKOPEO_VERSION#v}-linux-amd64.tar.gz"
    sudo tar -xzf /tmp/skopeo.tar.gz -C /tmp
    sudo cp /tmp/skopeo*/bin/skopeo /usr/local/bin/
    sudo chmod +x /usr/local/bin/skopeo
    sudo rm -rf /tmp/skopeo*
fi

# Method 1: Try to install from OS repositories first
echo "Attempting to install buildah from OS repositories..."
if command -v apt-get >/dev/null 2>&1; then
    # Set OS version for Ubuntu repositories
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "22.04")
    
    # Try Ubuntu 24.04 repository first
    echo "Adding containers repository for Ubuntu $UBUNTU_VERSION..."
    sudo mkdir -p /etc/apt/keyrings
    
    # Try the Kubic/containers repo with proper Ubuntu version
    REPO_URL="https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${UBUNTU_VERSION}"
    KEY_URL="${REPO_URL}/Release.key"
    
    echo "Checking repository: $REPO_URL"
    if curl -fsSL "$KEY_URL" | sudo gpg --dearmor -o /etc/apt/keyrings/libcontainers-stable-keyring.gpg; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/libcontainers-stable-keyring.gpg] $REPO_URL/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list > /dev/null
        
        sudo apt-get update
        if sudo apt-get install -y buildah 2>/dev/null; then
            echo "✅ Buildah installed from OS repositories"
        else
            echo "⚠️  OS repository installation failed, trying binary installation..."
            METHOD_2_INSTALL=true
        fi
    else
        echo "⚠️  Failed to get repository key, trying binary installation..."
        METHOD_2_INSTALL=true
    fi
else
    METHOD_2_INSTALL=true
fi

# Method 2: Binary installation if OS repos fail
if [ "${METHOD_2_INSTALL:-false}" = "true" ]; then
    echo "Installing buildah from binary..."
    BUILDAH_VERSION="1.38.0"
    
    # Download and install buildah
    echo "Downloading Buildah v${BUILDAH_VERSION}..."
    sudo wget -O /tmp/buildah.tar.gz "https://github.com/containers/buildah/releases/download/v${BUILDAH_VERSION}/buildah-v${BUILDAH_VERSION}-linux-amd64.tar.gz"
    
    if [ -f "/tmp/buildah.tar.gz" ]; then
        sudo tar -xzf /tmp/buildah.tar.gz -C /tmp
        sudo cp /tmp/buildah/bin/buildah /usr/local/bin/
        sudo cp /tmp/buildah/bin/runc /usr/local/bin/ 2>/dev/null || true
        sudo cp /tmp/buildah/bin/conmon /usr/local/bin/ 2>/dev/null || true
        sudo chmod +x /usr/local/bin/buildah
        sudo chmod +x /usr/local/bin/runc 2>/dev/null || true
        sudo chmod +x /usr/local/bin/conmon 2>/dev/null || true
        sudo rm -rf /tmp/buildah*
        
        echo "✅ Buildah installed from binary"
    else
        echo "❌ Failed to download buildah binary"
        echo "Trying alternative installation method..."
        
        # Fallback: Try to install from Ubuntu 24.04 packages
        echo "Attempting to install from Ubuntu packages..."
        if sudo apt-get update && sudo apt-get install -y buildah 2>/dev/null; then
            echo "✅ Buildah installed from Ubuntu packages"
        else
            echo "❌ All installation methods failed"
            echo "Please install buildah manually:"
            echo "  1. Visit https://github.com/containers/buildah/releases"
            echo "  2. Download the latest linux-amd64 tarball"
            echo "  3. Extract and copy buildah to /usr/local/bin/"
            exit 1
        fi
    fi
fi

# Configure buildah for container environments
echo "Configuring buildah for container environments..."
sudo mkdir -p /etc/containers

# Create containers configuration
sudo tee /etc/containers/registries.conf > /dev/null <<'EOF'
# Docker registry configuration
[registries.search]
registries = ['docker.io', 'registry.fedoraproject.org', 'quay.io', 'ghcr.io']

[registries.insecure]
registries = []

[registries.block]
registries = []
EOF

# Create storage configuration for containers
sudo tee /etc/containers/storage.conf > /dev/null <<'EOF'
# This file is is the configuration file for all tools that
# use the containers/storage library.
[storage]

# Default storage driver
driver = "overlay"

# Temporary storage location
runroot = "/var/run/containers/storage"

# Primary Read/Write location of container storage
graphroot = "/var/lib/containers/storage"

[storage.options]
# Size options for using the device mapper storage driver
# Additional image stores
additionalimagestores = [
]

# Options for using the overlay storage driver
overlay.mountopt = "nodev,metacopy=on"
overlay.mount_program = "/usr/bin/fuse-overlayfs"
overlay.ignore_chown_errors = "true"

EOF

# Create buildah configuration
sudo tee /usr/local/bin/buildah-container-config > /dev/null <<'EOF'
#!/bin/bash

# Buildah Container Configuration Script
# Configures buildah for optimal performance in containerized environments

echo "Configuring buildah for container environment..."

# Set environment variables for buildah
export BUILDAH_ISOLATION=chroot
export BUILDAH_FORMAT=docker
export BUILDAH_LAYERS_CACHE_DIR="/tmp/buildah-cache"
export STORAGE_DRIVER="overlay"
export REGISTRIES_CONFIG_PATH="/etc/containers/registries.conf"
export STORAGE_CONFIG_PATH="/etc/containers/storage.conf"

# Create cache directory
mkdir -p "$BUILDAH_LAYERS_CACHE_DIR"

# Ensure necessary directories exist
sudo mkdir -p /var/lib/containers/storage
sudo mkdir -p /var/run/containers/storage
sudo mkdir -p /tmp/buildah-cache

# Set proper permissions
sudo chmod 755 /var/lib/containers/storage
sudo chmod 755 /var/run/containers/storage
sudo chmod 755 /tmp/buildah-cache

echo "✅ Buildah environment configured"
echo "Environment variables set:"
echo "  • BUILDAH_ISOLATION=$BUILDAH_ISOLATION"
echo "  • BUILDAH_FORMAT=$BUILDAH_FORMAT"
echo "  • STORAGE_DRIVER=$STORAGE_DRIVER"
echo ""
echo "Buildah is ready for container operations!"
EOF

sudo chmod +x /usr/local/bin/buildah-container-config

# Create buildah helper script
sudo tee /usr/local/bin/buildah-helper > /dev/null <<'EOF'
#!/bin/bash

# Buildah Helper Script for Container Environments
# Provides common buildah operations optimized for containers

# Source configuration
source /usr/local/bin/buildah-container-config 2>/dev/null || true

show_help() {
    echo "Buildah Container Helper"
    echo "Usage: buildah-helper [command] [options]"
    echo ""
    echo "Commands:"
    echo "  build <dockerfile> <image_name>    Build image from Dockerfile"
    echo "  push <image_name> <registry>        Push image to registry"
    echo "  pull <image_name>                   Pull image from registry"
    echo "  list                                List local images"
    echo "  inspect <image_name>                Inspect image"
    echo "  rm <image_name>                     Remove image"
    echo "  config                              Show buildah configuration"
    echo "  help                                Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  REGISTRY                            Default registry (e.g., docker.io/username/)"
    echo "  TAG                                 Default tag (default: latest)"
}

build_image() {
    if [ -z "$2" ]; then
        echo "Usage: buildah-helper build <dockerfile> <image_name>"
        exit 1
    fi
    
    local dockerfile="$1"
    local image_name="$2"
    
    echo "🏗️  Building image: $image_name from $dockerfile"
    
    # Ensure buildah is configured
    buildah-container-config
    
    # Build the image
    buildah bud \
        --format=docker \
        --tls-verify=false \
        --storage-driver=overlay \
        --file "$dockerfile" \
        --tag "$image_name" \
        .
    
    if [ $? -eq 0 ]; then
        echo "✅ Build completed: $image_name"
    else
        echo "❌ Build failed: $image_name"
        exit 1
    fi
}

push_image() {
    if [ -z "$2" ]; then
        echo "Usage: buildah-helper push <image_name> <registry>"
        exit 1
    fi
    
    local image_name="$1"
    local registry="$2"
    
    echo "🚀 Pushing image: $image_name to $registry"
    
    # Configure buildah for container environment
    buildah-container-config
    
    # Push the image
    buildah push \
        --tls-verify=false \
        --storage-driver=overlay \
        "$image_name" \
        "docker://$registry$image_name"
    
    if [ $? -eq 0 ]; then
        echo "✅ Push completed: $registry$image_name"
    else
        echo "❌ Push failed: $image_name"
        exit 1
    fi
}

pull_image() {
    if [ -z "$2" ]; then
        echo "Usage: buildah-helper pull <image_name>"
        exit 1
    fi
    
    local image_name="$1"
    
    echo "📥 Pulling image: $image_name"
    
    # Configure buildah for container environment
    buildah-container-config
    
    # Pull the image
    buildah pull \
        --tls-verify=false \
        --storage-driver=overlay \
        "docker://$image_name"
    
    if [ $? -eq 0 ]; then
        echo "✅ Pull completed: $image_name"
    else
        echo "❌ Pull failed: $image_name"
        exit 1
    fi
}

list_images() {
    echo "📋 Local buildah images:"
    buildah images --format "table {{.Name}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
}

inspect_image() {
    if [ -z "$2" ]; then
        echo "Usage: buildah-helper inspect <image_name>"
        exit 1
    fi
    
    local image_name="$1"
    echo "🔍 Inspecting image: $image_name"
    buildah inspect "$image_name"
}

remove_image() {
    if [ -z "$2" ]; then
        echo "Usage: buildah-helper rm <image_name>"
        exit 1
    fi
    
    local image_name="$1"
    echo "🗑️  Removing image: $image_name"
    buildah rmi "$image_name"
}

show_config() {
    echo "🔧 Buildah Configuration:"
    echo "  • Registries config: /etc/containers/registries.conf"
    echo "  • Storage config: /etc/containers/storage.conf"
    echo "  • Storage driver: overlay"
    echo "  • Format: docker"
    echo ""
    echo "Environment Variables:"
    env | grep -E "^(BUILDAH|STORAGE|REGISTRY)" | sort
}

case "$1" in
    build)
        build_image "$2" "$3"
        ;;
    push)
        push_image "$2" "$3"
        ;;
    pull)
        pull_image "$2"
        ;;
    list)
        list_images
        ;;
    inspect)
        inspect_image "$2"
        ;;
    rm)
        remove_image "$2"
        ;;
    config)
        show_config
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use 'buildah-helper help' for usage information"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/buildah-helper

# Test installation
echo "Testing buildah installation..."
if command -v buildah >/dev/null 2>&1; then
    echo "✅ Buildah is installed: $(buildah --version)"
else
    echo "❌ Buildah installation failed"
    exit 1
fi

# Display final instructions
echo ""
echo "============================================"
echo "Buildah Container Installation Complete!"
echo "============================================"
echo ""
echo "🏗️  Buildah Environment:"
echo "  • Buildah: $(buildah --version)"
echo "  • Skopeo: $(skopeo --version 2>/dev/null || echo 'Not available')"
echo "  • Storage driver: overlay"
echo "  • Configuration: /etc/containers/"
echo ""
echo "🚀 Quick Start Commands:"
echo "  • Configure environment: buildah-container-config"
echo "  • Build image: buildah-helper build Dockerfile-jais2 jais2:latest"
echo "  • Push image: buildah-helper push jais2:latest docker.io/username/"
echo "  • List images: buildah-helper list"
echo "  • Show config: buildah-helper config"
echo ""
echo "📋 Files Created:"
echo "  • /etc/containers/registries.conf - Registry configuration"
echo "  • /etc/containers/storage.conf - Storage configuration"
echo "  • /usr/local/bin/buildah-helper - Helper script"
echo "  • /usr/local/bin/buildah-container-config - Configuration script"
echo ""
echo "⚠️  Container Notes:"
echo "  • Buildah works without daemon (unlike Docker)"
echo "  • Uses overlay storage driver for performance"
echo "  • Configured for container-optimized operation"
echo ""
echo "✅ Ready for buildah operations!"