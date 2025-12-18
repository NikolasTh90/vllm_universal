#!/bin/bash

# Buildah Build Script for JAIS2 Dockerfile (Root/Privileged Version)
# This script uses buildah with root privileges to handle container permission issues

set -e

echo "============================================"
echo "Building JAIS2 Dockerfile with Buildah (Root/Privileged)"
echo "============================================"

# Configuration
REGISTRY="${DOCKER_REGISTRY:-docker.io/nikolasth90/}"
IMAGE_NAME="${IMAGE_NAME:-vllm-universal}"
TAG="${TAG:-latest}"

# Allow command line overrides
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -r, --registry REGISTRY    Registry prefix (default: docker.io/nikolasth90/)"
            echo "  -t, --tag TAG              Tag suffix (default: latest)"
            echo "  -n, --name NAME            Image name (default: vllm-universal)"
            echo "  -h, --help                 Show this help"
            echo ""
            echo "This version runs with root privileges to handle container permission issues."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

FULL_IMAGE_NAME="${REGISTRY}${IMAGE_NAME}:jais2-${TAG}"

echo "🔧 Build Configuration:"
echo "  • Registry: $REGISTRY"
echo "  • Image Name: $IMAGE_NAME"
echo "  • Tag: jais2-$TAG"
echo "  • Full Image: $FULL_IMAGE_NAME"
echo "  • Mode: Root/Privileged"
echo ""

# Function to check if buildah is available
check_buildah() {
    if ! command -v buildah >/dev/null 2>&1; then
        echo "❌ Buildah is not installed"
        echo ""
        echo "To install buildah, run:"
        echo "  sudo ./install-buildah-container.sh"
        echo "  or"
        echo "  sudo ./install-buildah-ubuntu.sh"
        echo ""
        exit 1
    fi
    
    echo "✅ Buildah is available: $(buildah --version)"
}

# Function to configure buildah for root/privileged operation
configure_buildah_root() {
    echo "🔧 Configuring buildah for root/privileged operation..."
    
    # Set environment variables for privileged buildah
    export BUILDAH_ISOLATION=chroot
    export BUILDAH_FORMAT=docker
    export BUILDAH_LAYERS_CACHE_DIR="/tmp/buildah-cache"
    export STORAGE_DRIVER="overlay"
    export REGISTRIES_CONFIG_PATH="/etc/containers/registries.conf"
    export STORAGE_CONFIG_PATH="/etc/containers/storage.conf"
    
    # Disable user namespace handling
    export _BUILDAH_STARTED_IN_USERNS=""
    
    # Create necessary directories with proper permissions
    sudo mkdir -p /var/lib/containers/storage
    sudo mkdir -p /var/run/containers/storage
    mkdir -p "$BUILDAH_LAYERS_CACHE_DIR"
    
    # Set ownership and permissions
    sudo chown root:root /var/lib/containers/storage 2>/dev/null || true
    sudo chown root:root /var/run/containers/storage 2>/dev/null || true
    sudo chmod 755 /var/lib/containers/storage 2>/dev/null || true
    sudo chmod 755 /var/run/containers/storage 2>/dev/null || true
    chmod 755 "$BUILDAH_LAYERS_CACHE_DIR"
    
    echo "✅ Buildah root environment configured"
}

# Function to validate Dockerfile
validate_dockerfile() {
    local dockerfile="Dockerfile-jais2"
    
    if [ ! -f "$dockerfile" ]; then
        echo "❌ Dockerfile not found: $dockerfile"
        echo "Current directory: $(pwd)"
        echo "Available files:"
        ls -la *.sh Dockerfile* 2>/dev/null || echo "No Dockerfile found"
        exit 1
    fi
    
    echo "✅ Dockerfile found: $dockerfile"
    echo "📄 Dockerfile preview:"
    echo "---"
    head -20 "$dockerfile"
    echo "---"
}

# Function to build image with buildah (root version)
build_image_root() {
    local dockerfile="Dockerfile-jais2"
    
    echo "🏗️  Building JAIS2 image with buildah (root mode)..."
    echo "Image: $FULL_IMAGE_NAME"
    echo "Dockerfile: $dockerfile"
    echo ""
    
    # Build arguments for root mode
    local buildah_args=(
        --format=docker
        --tls-verify=false
        --storage-driver=overlay
        --file "$dockerfile"
        --tag "$FULL_IMAGE_NAME"
        --no-cache
        --userns= host
        --isolation=chroot
        --runtime=runc
        --squash  # Reduce layer size
    )
    
    # Try different approaches if needed
    echo "🔧 Attempting build with root privileges..."
    echo "Command: buildah bud ${buildah_args[*]} ."
    
    if buildah bud "${buildah_args[@]}" . 2>&1; then
        echo "✅ Build completed successfully: $FULL_IMAGE_NAME"
        return 0
    fi
    
    echo "⚠️  First attempt failed, trying alternative approach..."
    
    # Alternative approach without user namespace
    local alt_args=(
        --format=docker
        --tls-verify=false
        --storage-driver=overlay
        --file "$dockerfile"
        --tag "$FULL_IMAGE_NAME"
        --no-cache
        --isolation=chroot
    )
    
    echo "Command: buildah bud ${alt_args[*]} ."
    
    if buildah bud "${alt_args[@]}" . 2>&1; then
        echo "✅ Build completed successfully (alternative method): $FULL_IMAGE_NAME"
        return 0
    fi
    
    echo "❌ Build failed: $FULL_IMAGE_NAME"
    echo ""
    echo "🔧 Additional troubleshooting:"
    echo "  • Ensure container was started with --privileged flag"
    echo "  • Check if /proc/sys/user/max_user_namespaces allows sufficient namespaces"
    echo "  • Try running outside container if possible"
    exit 1
}

# Function to inspect built image
inspect_image() {
    echo "🔍 Inspecting built image..."
    buildah images --format "table {{.Name}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "$FULL_IMAGE_NAME" || echo "Image not found in local list"
    
    echo ""
    echo "📊 Image details:"
    if command -v jq >/dev/null 2>&1; then
        buildah inspect "$FULL_IMAGE_NAME" | jq -r '
            "  • ID: " + .FromImageID,
            "  • Created: " + .Created,
            "  • Architecture: " + .Architecture,
            "  • OS: " + .Os,
            "  • Size: " + (.Size | tostring) + " bytes"
        ' 2>/dev/null || echo "  • JSON inspection available with jq"
    else
        echo "  • Run 'buildah inspect $FULL_IMAGE_NAME' for details"
    fi
}

# Function to push image to registry
push_image() {
    echo "🚀 Pushing image to registry..."
    
    # Check if we're pushing to a real registry
    if [[ "$REGISTRY" == "docker.io/nikolasth90/" ]] || [[ "$REGISTRY" == *".com/" ]] || [[ "$REGISTRY" == *".io/" ]]; then
        echo "Registry detected: $REGISTRY"
        echo "🔑 Please ensure you're authenticated to the registry"
        
        # Try to push with buildah
        if buildah push \
            --tls-verify=false \
            --storage-driver=overlay \
            "$FULL_IMAGE_NAME" \
            "docker://$FULL_IMAGE_NAME" 2>&1; then
            echo "✅ Push completed successfully: $FULL_IMAGE_NAME"
        else
            echo "❌ Push failed: $FULL_IMAGE_NAME"
            echo ""
            echo "Troubleshooting:"
            echo "  • Ensure you're logged in: buildah login docker.io"
            echo "  • Check registry name: $REGISTRY"
            echo "  • Verify network connectivity"
            exit 1
        fi
    else
        echo "ℹ️  Skipping push - no external registry configured"
        echo "   To push to a registry, set DOCKER_REGISTRY environment variable:"
        echo "   export DOCKER_REGISTRY=your-registry.com/"
        echo "   Then run this script again"
    fi
}

# Function to provide usage examples
show_usage() {
    echo ""
    echo "============================================"
    echo "✅ JAIS2 Build Process Complete (Root Mode)!"
    echo "============================================"
    echo ""
    echo "🚀 Built Image: $FULL_IMAGE_NAME"
    echo ""
    echo "📋 Usage Examples:"
    echo "  • Run with buildah:"
    echo "     buildah run --rm $FULL_IMAGE_NAME -- --help"
    echo ""
    echo "  • Run with podman (if available):"
    echo "     podman run -p 8000:8000 $FULL_IMAGE_NAME"
    echo ""
    echo "  • Save image to tar:"
    echo "     buildah push $FULL_IMAGE_NAME docker-archive:/tmp/jais2-image.tar"
    echo ""
    echo "  • Push to different registry:"
    echo "     buildah push $FULL_IMAGE_NAME docker://ghcr.io/username/jais2:latest"
    echo ""
    echo "🔧 Buildah Commands:"
    echo "  • List images: buildah images"
    echo "  • Remove image: buildah rmi $FULL_IMAGE_NAME"
    echo "  • Inspect image: buildah inspect $FULL_IMAGE_NAME"
    echo ""
    echo "📝 Environment Variables for JAIS2:"
    echo "  • VLLM_MODEL_NAME - Model to serve (default: jais-13b-chat)"
    echo "  • VLLM_GPU_UTIL - GPU utilization (default: 0.95)"
    echo "  • VLLM_MAX_MODEL_LEN - Maximum model length (default: 8192)"
    echo ""
    echo "🔑 Root Mode Notes:"
    echo "  • This script used root privileges to handle container permission issues"
    echo "  • For non-privileged environments, use: ./build-jais2-with-buildah.sh"
    echo "  • Container should be started with --privileged for best compatibility"
}

# Main execution
main() {
    echo "Starting JAIS2 build process with buildah (root mode)..."
    echo ""
    
    # Check prerequisites
    check_buildah
    configure_buildah_root
    validate_dockerfile
    
    # Build the image
    build_image_root
    inspect_image
    
    # Push to registry
    push_image
    
    # Show usage information
    show_usage
}

# Handle script interruption
trap 'echo ""; echo "❌ Build interrupted"; exit 1' INT TERM

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  This script requires root privileges"
    echo "   Running with sudo..."
    exec sudo "$0" "$@"
fi

# Run main function
main "$@"