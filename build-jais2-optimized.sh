#!/bin/bash

# Optimized Build Script for JAIS2 Dockerfile
# This script builds the optimized JAIS2 Dockerfile with memory and speed improvements

set -e

echo "============================================"
echo "Building Optimized JAIS2 Dockerfile"
echo "============================================"

# Configuration
REGISTRY="${DOCKER_REGISTRY:-docker.io/nikolasth90/}"
IMAGE_NAME="${IMAGE_NAME:-vllm-universal}"
TAG="${TAG:-jais2-optimized}"
FULL_IMAGE_NAME="${REGISTRY}${IMAGE_NAME}:${TAG}"

# Memory and build optimization settings
BUILD_MEMORY_LIMIT="${BUILD_MEMORY_LIMIT:-4g}"
BUILD_CPUS="${BUILD_CPUS:-$(nproc)}"
DOCKER_BUILDKIT=1

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
        -m|--memory)
            BUILD_MEMORY_LIMIT="$2"
            shift 2
            ;;
        -c|--cpus)
            BUILD_CPUS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -r, --registry REGISTRY    Registry prefix (default: docker.io/nikolasth90/)"
            echo "  -t, --tag TAG              Tag suffix (default: latest)"
            echo "  -n, --name NAME            Image name (default: vllm-universal)"
            echo "  -m, --memory LIMIT         Build memory limit (default: 4g)"
            echo "  -c, --cpus COUNT           CPU count for build (default: all cores)"
            echo "  -h, --help                 Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  DOCKER_REGISTRY            Registry prefix"
            echo "  IMAGE_NAME                 Base image name"
            echo "  TAG                        Tag suffix"
            echo "  BUILD_MEMORY_LIMIT         Memory limit for build"
            echo "  BUILD_CPUS                 CPU count for build"
            echo ""
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
FULL_IMAGE_NAME="${REGISTRY}${IMAGE_NAME}:${TAG}"

echo "🔧 Optimized Build Configuration:"
echo "  • Registry: $REGISTRY"
echo "  • Image Name: $IMAGE_NAME"
echo "  • Tag: $TAG"
echo "  • Full Image: $FULL_IMAGE_NAME"
echo "  • Memory Limit: $BUILD_MEMORY_LIMIT"
echo "  • CPU Count: $BUILD_CPUS"
echo ""

# Function to check if buildah is available
check_buildah() {
    if command -v buildah >/dev/null 2>&1; then
        echo "✅ Buildah is available: $(buildah --version)"
        HAS_BUILDAH=true
    else
        echo "❌ Buildah is not installed"
        HAS_BUILDAH=false
    fi
}

# Function to check if docker is available
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        echo "✅ Docker is available: $(docker --version)"
        HAS_DOCKER=true
    else
        echo "❌ Docker is not installed"
        HAS_DOCKER=false
    fi
}

# Function to validate Dockerfile
validate_dockerfile() {
    local dockerfile="Dockerfile-jais2-optimized"
    
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

# Function to build with optimized Docker
build_with_docker() {
    echo "🐳 Building with optimized Docker settings..."
    
    # Enable BuildKit with optimizations
    export DOCKER_BUILDKIT=1
    export BUILDKIT_STEP_LOG_MAX_SIZE=10000000
    export BUILDKIT_STEP_LOG_MAX_SPEED=100
    export BUILDKIT_INLINE_CACHE=1
    
    # Check if Docker buildx is available and use it for better resource control
    if docker buildx version >/dev/null 2>&1; then
        echo "Using Docker BuildKit (buildx) with CPU limit: $BUILD_CPUS cores"
        
        # Build arguments with memory and CPU limits using buildx
        local docker_args=(
            buildx build
            --file Dockerfile-jais2-optimized
            --tag "$FULL_IMAGE_NAME"
            --build-arg BUILDKIT_INLINE_CACHE=1
            --progress=plain
            --memory="$BUILD_MEMORY_LIMIT"
            --cpus="$BUILD_CPUS"
            --load
        )
        
        echo "Running: docker ${docker_args[*]} ."
        
        if docker "${docker_args[@]}" .; then
            echo "✅ Docker buildx completed: $FULL_IMAGE_NAME"
            return 0
        else
            echo "❌ Docker buildx failed, falling back to standard Docker build"
        fi
    fi
    
    echo "Using standard Docker build with memory limit only"
    
    # Fallback to standard Docker build
    local docker_args=(
        build
        --file Dockerfile-jais2-optimized
        --tag "$FULL_IMAGE_NAME"
        --build-arg BUILDKIT_INLINE_CACHE=1
        --progress=plain
        --memory="$BUILD_MEMORY_LIMIT"
        --no-cache
    )
    
    echo "Running: docker ${docker_args[*]} ."
    
    if docker "${docker_args[@]}" .; then
        echo "✅ Docker build completed: $FULL_IMAGE_NAME"
        return 0
    else
        echo "❌ Docker build failed"
        return 1
    fi
}

# Function to build with optimized buildah
build_with_buildah() {
    echo "🏗️  Building with optimized buildah settings..."
    
    # Configure buildah environment for memory optimization
    export BUILDAH_ISOLATION=chroot
    export BUILDAH_FORMAT=docker
    export BUILDAH_LAYERS_CACHE_DIR="/tmp/buildah-cache"
    export STORAGE_DRIVER="overlay"
    
    # Build arguments with optimizations
    local buildah_args=(
        --format=docker
        --tls-verify=false
        --storage-driver=overlay
        --file Dockerfile-jais2-optimized
        --tag "$FULL_IMAGE_NAME"
        --no-cache
        --jobs="$BUILD_CPUS"
    )
    
    # Add container-specific flags
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
        echo "🐳 Using container-specific buildah flags..."
        buildah_args+=(--userns=host --isolation=chroot)
    fi
    
    echo "Running: buildah bud ${buildah_args[*]} ."
    
    if buildah bud "${buildah_args[@]}" .; then
        echo "✅ Buildah build completed: $FULL_IMAGE_NAME"
        return 0
    else
        echo "❌ Buildah build failed"
        return 1
    fi
}

# Function to choose build tool
choose_build_tool() {
    if [ "$HAS_BUILDAH" = true ]; then
        echo "🔧 Choosing Buildah for optimized build"
        return 0  # Return 0 to indicate Buildah
    elif [ "$HAS_DOCKER" = true ]; then
        echo "🔧 Choosing Docker for optimized build"
        return 1  # Return 1 to indicate Docker
    else
        echo "❌ No build tools available"
        exit 1
    fi
}

# Function to push image
push_image() {
    local build_tool="$1"
    
    echo "🚀 Pushing image using $build_tool..."
    
    if [[ "$REGISTRY" == "docker.io/nikolasth90/" ]] || [[ "$REGISTRY" == *".com/" ]] || [[ "$REGISTRY" == *".io/" ]]; then
        echo "Registry detected: $REGISTRY"
        
        if [ "$build_tool" = "buildah" ]; then
            if buildah push \
                --tls-verify=false \
                --storage-driver=overlay \
                "$FULL_IMAGE_NAME" \
                "docker://$FULL_IMAGE_NAME"; then
                echo "✅ Push completed with buildah: $FULL_IMAGE_NAME"
                return 0
            else
                echo "❌ Buildah push failed"
                return 1
            fi
        elif [ "$build_tool" = "docker" ]; then
            if docker push "$FULL_IMAGE_NAME"; then
                echo "✅ Push completed with Docker: $FULL_IMAGE_NAME"
                return 0
            else
                echo "❌ Docker push failed"
                return 1
            fi
        fi
    else
        echo "ℹ️  Skipping push - no external registry configured"
        return 0
    fi
}

# Function to show build tips
show_optimization_tips() {
    echo ""
    echo "🚀 Build Optimization Applied:"
    echo "  • Memory limit: $BUILD_MEMORY_LIMIT"
    echo "  • CPU limit: $BUILD_CPUS cores"
    echo "  • Shallow git clone (depth 1)"
    echo "  • Pip cache optimization"
    echo "  • BuildKit enabled for Docker"
    echo "  • Cleanup of temporary files and cache"
    echo ""
    
    echo "💡 Additional Memory Tips:"
    echo "  • Use --memory flag to limit build memory"
    echo "  • Set BUILD_MEMORY_LIMIT environment variable"
    echo "  • Use Docker BuildKit for efficient layer caching"
    echo "  • Clear pip cache during build (pip cache purge)"
    echo ""
    
    echo "⚡ Speed Optimization Tips:"
    echo "  • Use more CPUs with --cpus flag"
    echo "  • Enable BuildKit for parallel builds"
    echo "  • Use shallow git clones (--depth 1)"
    echo "  • Clean up package caches during build"
    echo ""
}

# Main execution
main() {
    echo "Starting optimized JAIS2 build process..."
    echo ""
    
    # Check prerequisites
    check_buildah
    check_docker
    validate_dockerfile
    
    # Choose build tool
    if choose_build_tool; then
        # Use buildah
        build_with_buildah
        push_image "buildah"
    else
        # Use docker
        build_with_docker
        push_image "docker"
    fi
    
    # Show optimization tips
    show_optimization_tips
    
    # Show final status
    echo ""
    echo "=========================================="
    echo "✅ Optimized JAIS2 Build Complete!"
    echo "=========================================="
    echo ""
    echo "🚀 Built Image: $FULL_IMAGE_NAME"
    echo ""
    echo "📋 Next Steps:"
    echo "  • Test the image: docker run -p 8000:8000 $FULL_IMAGE_NAME"
    echo "  • Check image size: docker images | grep $FULL_IMAGE_NAME"
    echo "  • Compare with original build to measure improvements"
}

# Handle script interruption
trap 'echo ""; echo "❌ Build interrupted"; exit 1' INT TERM

# Run main function
main "$@"