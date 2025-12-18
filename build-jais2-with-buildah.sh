#!/bin/bash

# Buildah Build Script for JAIS2 Dockerfile
# This script uses buildah to build the JAIS2 Dockerfile and push to repository

set -e

echo "============================================"
echo "Building JAIS2 Dockerfile with Buildah"
echo "============================================"

# Configuration
REGISTRY="${DOCKER_REGISTRY:-docker.io/nikolasth90/}"
IMAGE_NAME="${IMAGE_NAME:-vllm-universal}"
TAG="${TAG:-latest}"
FULL_IMAGE_NAME="${REGISTRY}${IMAGE_NAME}:jais2-${TAG}"

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
            echo "Environment Variables:"
            echo "  DOCKER_REGISTRY            Registry prefix"
            echo "  IMAGE_NAME                 Base image name"
            echo "  TAG                        Tag suffix"
            echo ""
            echo "Example:"
            echo "  $0 -r myregistry.com/ -t v1.0 -n myjais-image"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# Update full image name with potential changes
FULL_IMAGE_NAME="${REGISTRY}${IMAGE_NAME}:jais2-${TAG}"

echo "🔧 Build Configuration:"
echo "  • Registry: $REGISTRY"
echo "  • Image Name: $IMAGE_NAME"
echo "  • Tag: jais2-$TAG"
echo "  • Full Image: $FULL_IMAGE_NAME"
echo ""

# Function to check if buildah is available
check_buildah() {
    if ! command -v buildah >/dev/null 2>&1; then
        echo "❌ Buildah is not installed"
        echo ""
        echo "To install buildah, run:"
        echo "  sudo ./install-buildah-container.sh"
        echo ""
        exit 1
    fi
    
    echo "✅ Buildah is available: $(buildah --version)"
}

# Function to configure buildah environment
configure_buildah() {
    echo "🔧 Configuring buildah for container environment..."
    
    # Set environment variables for buildah
    export BUILDAH_ISOLATION=chroot
    export BUILDAH_FORMAT=docker
    export BUILDAH_LAYERS_CACHE_DIR="/tmp/buildah-cache"
    export STORAGE_DRIVER="overlay"
    export REGISTRIES_CONFIG_PATH="/etc/containers/registries.conf"
    export STORAGE_CONFIG_PATH="/etc/containers/storage.conf"
    
    # Create necessary directories
    sudo mkdir -p /var/lib/containers/storage
    sudo mkdir -p /var/run/containers/storage
    mkdir -p "$BUILDAH_LAYERS_CACHE_DIR"
    
    # Set permissions
    sudo chmod 755 /var/lib/containers/storage 2>/dev/null || true
    sudo chmod 755 /var/run/containers/storage 2>/dev/null || true
    chmod 755 "$BUILDAH_LAYERS_CACHE_DIR"
    
    echo "✅ Buildah environment configured"
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

# Function to build image with buildah
build_image() {
    local dockerfile="Dockerfile-jais2"
    
    echo "🏗️  Building JAIS2 image with buildah..."
    echo "Image: $FULL_IMAGE_NAME"
    echo "Dockerfile: $dockerfile"
    echo ""
    
    # Build the image using buildah
    buildah bud \
        --format=docker \
        --tls-verify=false \
        --storage-driver=overlay \
        --file "$dockerfile" \
        --tag "$FULL_IMAGE_NAME" \
        --no-cache \
        .
    
    if [ $? -eq 0 ]; then
        echo "✅ Build completed successfully: $FULL_IMAGE_NAME"
    else
        echo "❌ Build failed: $FULL_IMAGE_NAME"
        exit 1
    fi
}

# Function to inspect built image
inspect_image() {
    echo "🔍 Inspecting built image..."
    buildah images --format "table {{.Name}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "$FULL_IMAGE_NAME" || echo "Image not found in local list"
    
    echo ""
    echo "📊 Image details:"
    buildah inspect "$FULL_IMAGE_NAME" | jq -r '
        "  • ID: " + .FromImageID,
        "  • Created: " + .Created,
        "  • Architecture: " + .Architecture,
        "  • OS: " + .Os,
        "  • Size: " + (.Size | tostring) + " bytes"
    ' 2>/dev/null || echo "  • JSON inspection not available (jq missing)"
}

# Function to push image to registry
push_image() {
    echo "🚀 Pushing image to registry..."
    
    # Check if we're pushing to a real registry (not just local)
    if [[ "$REGISTRY" == "docker.io/nikolasth90/" ]] || [[ "$REGISTRY" == *".com/" ]] || [[ "$REGISTRY" == *".io/" ]]; then
        echo "Registry detected: $REGISTRY"
        echo "🔑 Please ensure you're authenticated to the registry"
        
        # Try to push with buildah
        buildah push \
            --tls-verify=false \
            --storage-driver=overlay \
            "$FULL_IMAGE_NAME" \
            "docker://$FULL_IMAGE_NAME"
        
        if [ $? -eq 0 ]; then
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
    echo "✅ JAIS2 Build Process Complete!"
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
}

# Main execution
main() {
    echo "Starting JAIS2 build process with buildah..."
    echo ""
    
    # Check prerequisites
    check_buildah
    configure_buildah
    validate_dockerfile
    
    # Build the image
    build_image
    inspect_image
    
    # Push to registry
    push_image
    
    # Show usage information
    show_usage
}

# Handle script interruption
trap 'echo ""; echo "❌ Build interrupted"; exit 1' INT TERM

# Run main function
main "$@"