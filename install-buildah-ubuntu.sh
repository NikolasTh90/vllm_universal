#!/bin/bash

# Simple Buildah Installation for Ubuntu 24.04
# This script installs buildah using Ubuntu's package manager directly

set -e

echo "============================================"
echo "Installing Buildah for Ubuntu 24.04"
echo "============================================"

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    echo "⚠️  This script is optimized for Ubuntu 24.04"
    echo "Your system: $(cat /etc/os-release | grep PRETTY_NAME || echo 'Unknown')"
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Update package lists
echo "📦 Updating package lists..."
sudo apt-get update

# Install required dependencies
echo "📦 Installing dependencies..."
sudo apt-get install -y --no-install-recommends \
    curl \
    wget \
    tar \
    ca-certificates \
    gnupg \
    software-properties-common \
    apt-transport-https

# Method 1: Try to install from Ubuntu repositories (preferred)
echo "🏗️  Attempting to install buildah from Ubuntu repositories..."
if sudo apt-get install -y buildah 2>/dev/null; then
    echo "✅ Buildah installed from Ubuntu repositories"
    BUILDAH_INSTALLED=true
else
    echo "⚠️  Ubuntu repository installation failed, trying alternative method..."
    BUILDAH_INSTALLED=false
fi

# Method 2: Try containers repository if Ubuntu repos fail
if [ "$BUILDAH_INSTALLED" = "false" ]; then
    echo "🏗️  Adding containers repository..."
    
    # Remove any existing containers repository
    sudo rm -f /etc/apt/sources.list.d/devel:kubic:*.list
    sudo rm -f /etc/apt/keyrings/libcontainers-*.gpg
    
    # Add the stable containers repository
    sudo mkdir -p /etc/apt/keyrings
    
    # Get Ubuntu version
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
    
    # Try different repository URLs
    REPOS_TO_TRY=(
        "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${UBUNTU_CODENAME}"
        "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04"
        "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_22.04"
    )
    
    for repo_url in "${REPOS_TO_TRY[@]}"; do
        echo "Trying repository: $repo_url"
        key_url="${repo_url}/Release.key"
        
        if curl -fsSL "$key_url" | sudo gpg --dearmor -o /etc/apt/keyrings/libcontainers-keyring.gpg; then
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/libcontainers-keyring.gpg] $repo_url/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers.list > /dev/null
            
            sudo apt-get update
            if sudo apt-get install -y buildah 2>/dev/null; then
                echo "✅ Buildah installed from containers repository"
                BUILDAH_INSTALLED=true
                break
            else
                echo "❌ Failed to install from this repository"
            fi
        else
            echo "❌ Failed to get repository key from $key_url"
        fi
    done
fi

# Method 3: Binary installation as last resort
if [ "$BUILDAH_INSTALLED" = "false" ]; then
    echo "🏗️  Installing buildah from binary..."
    BUILDAH_VERSION="1.38.0"
    
    # Download and install buildah
    echo "Downloading Buildah v${BUILDAH_VERSION}..."
    if wget -O /tmp/buildah.tar.gz "https://github.com/containers/buildah/releases/download/v${BUILDAH_VERSION}/buildah-v${BUILDAH_VERSION}-linux-amd64.tar.gz"; then
        tar -xzf /tmp/buildah.tar.gz -C /tmp
        sudo cp /tmp/buildah/bin/buildah /usr/local/bin/
        sudo cp /tmp/buildah/bin/runc /usr/local/bin/ 2>/dev/null || true
        sudo chmod +x /usr/local/bin/buildah
        sudo chmod +x /usr/local/bin/runc 2>/dev/null || true
        rm -rf /tmp/buildah*
        
        echo "✅ Buildah installed from binary"
        BUILDAH_INSTALLED=true
    else
        echo "❌ Failed to download buildah binary"
    fi
fi

# Check if buildah was successfully installed
if [ "$BUILDAH_INSTALLED" = "true" ]; then
    if command -v buildah >/dev/null 2>&1; then
        echo ""
        echo "✅ Buildah installation successful!"
        echo "Version: $(buildah --version)"
        
        # Create basic configuration
        echo ""
        echo "🔧 Setting up basic configuration..."
        sudo mkdir -p /etc/containers
        
        # Create registries.conf if it doesn't exist
        if [ ! -f "/etc/containers/registries.conf" ]; then
            sudo tee /etc/containers/registries.conf > /dev/null <<'EOF'
[registries.search]
registries = ['docker.io', 'registry.fedoraproject.org', 'quay.io', 'ghcr.io']

[registries.insecure]
registries = []

[registries.block]
registries = []
EOF
            echo "✅ Created /etc/containers/registries.conf"
        fi
        
        # Create storage.conf if it doesn't exist
        if [ ! -f "/etc/containers/storage.conf" ]; then
            sudo tee /etc/containers/storage.conf > /dev/null <<'EOF'
[storage]
driver = "overlay"
runroot = "/var/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
overlay.mountopt = "nodev,metacopy=on"
overlay.ignore_chown_errors = "true"
EOF
            echo "✅ Created /etc/containers/storage.conf"
        fi
        
        echo ""
        echo "🚀 Buildah is ready to use!"
        echo ""
        echo "Next steps:"
        echo "1. Setup registry authentication: ./buildah-registry-auth.sh setup-dockerhub"
        echo "2. Build your JAIS2 image: ./build-jais2-with-buildah.sh"
        echo "3. Test the setup: ./test-buildah-setup.sh"
        echo ""
        echo "Buildah location: $(which buildah)"
        echo "Configuration: /etc/containers/"
        
    else
        echo "❌ Buildah not found after installation"
        exit 1
    fi
else
    echo ""
    echo "❌ All installation methods failed"
    echo ""
    echo "Manual installation instructions:"
    echo "1. Visit https://github.com/containers/buildah/releases"
    echo "2. Download the latest linux-amd64 tarball"
    echo "3. Extract and copy buildah to /usr/local/bin/"
    echo "4. Make it executable: chmod +x /usr/local/bin/buildah"
    exit 1
fi