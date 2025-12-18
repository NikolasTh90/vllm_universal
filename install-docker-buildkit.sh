#!/bin/bash

# Docker BuildKit Installation Script
# This script installs and configures Docker BuildKit for optimized builds

set -e

echo "============================================"
echo "Installing Docker BuildKit for Optimized Builds"
echo "============================================"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root for security reasons"
   echo "Please run as a regular user with sudo privileges"
   exit 1
fi

echo "🔍 Checking current Docker setup..."

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "You can use: ./install-docker-ubuntu2404.sh"
    exit 1
fi

echo "✅ Docker found: $(docker --version)"

# Check if buildx is already installed
if docker buildx version >/dev/null 2>&1; then
    echo "✅ Docker BuildKit (buildx) is already available: $(docker buildx version)"
    BUILDX_AVAILABLE=true
elif command -v docker-buildx >/dev/null 2>&1; then
    echo "✅ Docker BuildKit (buildx) is already installed: $(docker-buildx version)"
    BUILDX_AVAILABLE=true
else
    echo "📦 Installing Docker BuildKit (buildx)..."
    BUILDX_AVAILABLE=false
    
    # Update package index
    sudo apt-get update
    
    # Install buildx plugin
    sudo apt-get install -y docker-buildx-plugin
    
    if docker buildx version >/dev/null 2>&1 || command -v docker-buildx >/dev/null 2>&1; then
        echo "✅ Docker BuildKit installed successfully"
        BUILDX_AVAILABLE=true
    else
        echo "❌ Failed to install Docker BuildKit via package manager"
        echo "Trying alternative installation method..."
        
        # Try downloading latest buildx binary
        BUILDX_VERSION=$(curl -s https://api.github.com/repos/docker/buildx/releases/latest | grep tag_name | cut -d '"' -f 4)
        if [ -z "$BUILDX_VERSION" ]; then
            BUILDX_VERSION="v0.25.0"  # Fallback version
        fi
        
        echo "Downloading buildx ${BUILDX_VERSION}..."
        sudo mkdir -p /usr/local/lib/docker/cli-plugins
        sudo curl -L "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64" -o /usr/local/lib/docker/cli-plugins/docker-buildx
        sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
        
        if docker buildx version >/dev/null 2>&1; then
            echo "✅ Docker BuildKit installed successfully via binary"
            BUILDX_AVAILABLE=true
        else
            echo "❌ Failed to install Docker BuildKit"
            exit 1
        fi
    fi
fi

if [ "$BUILDX_AVAILABLE" = true ]; then
    echo ""
    echo "🔧 Configuring BuildKit..."
    
    # Create a new builder instance
    echo "Creating BuildKit builder instance..."
    if docker buildx ls | grep -q "mybuilder"; then
        echo "Builder 'mybuilder' already exists, using it..."
        docker buildx use mybuilder
    else
        echo "Creating new builder 'mybuilder'..."
        docker buildx create --name mybuilder --driver docker-container --use
    fi
else
    echo "❌ BuildKit not available, cannot proceed"
    exit 1
fi

# Bootstrap the builder
echo "Bootstrapping builder..."
docker buildx inspect --bootstrap

# Verify builder is working
echo "Verifying BuildKit setup..."
docker buildx inspect

echo ""
echo "🚀 Testing BuildKit with a simple build..."

# Create a test Dockerfile
cat > Dockerfile.buildkit-test << 'EOF'
FROM alpine:latest
RUN echo "BuildKit is working!" > /test.txt
CMD cat /test.txt
EOF

# Test build with BuildKit
if docker buildx build --file Dockerfile.buildkit-test --tag buildkit-test --load .; then
    echo "✅ BuildKit test successful!"
    
    # Clean up test
    docker rmi buildkit-test >/dev/null 2>&1 || true
    rm -f Dockerfile.buildkit-test
else
    echo "❌ BuildKit test failed"
    exit 1
fi

echo ""
echo "🔍 BuildKit Configuration Info:"
echo "Current builder: $(docker buildx inspect --format '{{.Name}}')"
echo "BuildKit version: $(docker buildx version)"
echo "Platforms: $(docker buildx inspect --format '{{json .Platforms}}')"

echo ""
echo "📋 BuildKit Benefits for vLLM Builds:"
echo "  • Parallel execution of RUN commands"
echo "  • Better layer caching and reuse"
echo "  • Improved memory management"
echo "  • 20-40% faster builds for complex Dockerfiles"
echo "  • Better error handling and logging"

echo ""
echo "⚡ Performance Tips:"
echo "  • Use 'docker buildx build' instead of 'docker build'"
echo "  • Enable cache-from/cache-to for faster incremental builds"
echo "  • Use '--progress=plain' for better build visibility"
echo "  • Consider Docker Bake for multi-stage optimizations"

echo ""
echo "🔧 BuildKit Memory and CPU Control:"
echo "  • Memory limit: --memory=55g (working)"
echo "  • CPU control: Use builder with resource constraints"
echo "  • Resource limits are enforced at builder level"

echo ""
echo "=========================================="
echo "✅ Docker BuildKit Installation Complete!"
echo "=========================================="
echo ""
echo "📋 Next Steps:"
echo "  1. Use 'docker buildx build' for optimized builds"
echo "  2. Try the enhanced build script: ./build-jais2-buildkit.sh"
echo "  3. Consider using Docker Bake for production builds"
echo ""
echo "🚀 Your existing optimized Dockerfile is ready!"
echo "   BuildKit will make it even faster and more efficient."
echo ""
echo "💡 Test with:"
echo "   docker buildx build --file Dockerfile-jais2-optimized --tag test:v1 --memory=55g --load ."