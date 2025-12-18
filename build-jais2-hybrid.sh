#!/bin/bash

# Hybrid Build Script for JAIS2 Dockerfile
# Automatically chooses between buildah and Docker based on environment capabilities

set -e

echo "============================================"
echo "Hybrid Build Script for JAIS2 Dockerfile"
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
        --force-docker)
            FORCE_DOCKER=true
            shift
            ;;
        --force-buildah)
            FORCE_BUILDAH=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -r, --registry REGISTRY    Registry prefix (default: docker.io/nikolasth90/)"
            echo "  -t, --tag TAG              Tag suffix (default: latest)"
            echo "  -n, --name NAME            Image name (default: vllm-universal)"
            echo "  --force-docker             Force using Docker even if buildah available"
            echo "  --force-buildah            Force using buildah even in restricted environment"
            echo "  -h, --help                 Show this help"
            echo ""
            echo "This script automatically detects the best build tool for your environment."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

echo "🔧 Build Configuration:"
echo "  • Registry: $REGISTRY"
echo "  • Image Name: $IMAGE_NAME"
echo "  • Tag: jais2-$TAG"
echo "  • Full Image: $FULL_IMAGE_NAME"
echo ""

# Function to detect environment capabilities
detect_environment() {
    echo "🔍 Detecting environment capabilities..."
    
    HAS_BUILDAH=false
    HAS_DOCKER=false
    IN_CONTAINER=false
    HAS_PRIVILEGED=false
    
    # Check for buildah
    if command -v buildah >/dev/null 2>&1; then
        HAS_BUILDAH=true
        echo "✅ Buildah available: $(buildah --version 2>/dev/null | head -1 || echo 'version unknown')"
    fi
    
    # Check for docker
    if command -v docker >/dev/null 2>&1; then
        HAS_DOCKER=true
        echo "✅ Docker available: $(docker --version 2>/dev/null || echo 'version unknown')"
    fi
    
    # Check if in container
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
        IN_CONTAINER=true
        echo "🐳 Running in container environment"
    else
        echo "🖥️  Running on host system"
    fi
    
    # Check for privileged container
    if [ "$IN_CONTAINER" = true ]; then
        # Try to detect if we can create user namespaces
        if unshare --user true >/dev/null 2>&1; then
            HAS_PRIVILEGED=true
            echo "✅ Container has user namespace capabilities"
        else
            echo "❌ Container lacks user namespace capabilities"
        fi
    fi
    
    # System info
    echo "📋 Environment summary:"
    echo "  • Buildah: $HAS_BUILDAH"
    echo "  • Docker: $HAS_DOCKER"
    echo "  • Container: $IN_CONTAINER"
    echo "  • Privileged: $HAS_PRIVILEGED"
    echo ""
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
}

# Function to install Docker if needed
install_docker_if_needed() {
    if [ "$HAS_DOCKER" = false ]; then
        echo "🐳 Docker not found, attempting to install..."
        
        # Check if we have installation scripts
        if [ -f "./install-docker-container.sh" ]; then
            echo "Installing Docker for container environment..."
            sudo ./install-docker-container.sh
            if command -v docker >/dev/null 2>&1; then
                HAS_DOCKER=true
                echo "✅ Docker installed successfully"
            else
                echo "❌ Docker installation failed"
                return 1
            fi
        elif [ -f "./install-docker-ubuntu2404.sh" ]; then
            echo "Installing Docker for Ubuntu 24.04..."
            sudo ./install-docker-ubuntu2404.sh
            if command -v docker >/dev/null 2>&1; then
                HAS_DOCKER=true
                echo "✅ Docker installed successfully"
            else
                echo "❌ Docker installation failed"
                return 1
            fi
        else
            echo "❌ No Docker installation script found"
            return 1
        fi
    fi
}

# Function to setup Docker daemon in container
setup_docker_in_container() {
    if [ "$IN_CONTAINER" = true ] && [ "$HAS_DOCKER" = true ]; then
        echo "🐳 Setting up Docker daemon in container..."
        
        # Check if Docker daemon is running
        if ! docker version >/dev/null 2>&1; then
            echo "Starting Docker daemon..."
            
            # Create necessary directories
            sudo mkdir -p /var/run /var/lib/docker
            
            # Start Docker daemon
            sudo dockerd \
                --host=unix:///var/run/docker.sock \
                --host=tcp://127.0.0.1:2375 \
                --storage-driver=overlay2 \
                --exec-root=/var/run/docker \
                --data-root=/var/lib/docker \
                --iptables=false \
                --ip-masq=false \
                --bridge=none \
                --userland-proxy=false \
                --live-restore \
                --log-level=warn > /dev/null 2>&1 &
            
            DOCKER_PID=$!
            echo "Docker daemon started with PID: $DOCKER_PID"
            
            # Wait for Docker to be ready
            echo "Waiting for Docker to be ready..."
            for i in {1..30}; do
                if docker version >/dev/null 2>&1; then
                    echo "✅ Docker is ready!"
                    break
                fi
                sleep 1
            done
            
            # Check if Docker is actually ready
            if ! docker version >/dev/null 2>&1; then
                echo "❌ Docker failed to start properly"
                kill $DOCKER_PID 2>/dev/null || true
                return 1
            fi
        else
            echo "✅ Docker daemon is already running"
        fi
    fi
}

# Function to build with buildah
build_with_buildah() {
    echo "🏗️  Building with buildah..."
    
    # Configure buildah environment
    export BUILDAH_ISOLATION=chroot
    export BUILDAH_FORMAT=docker
    export BUILDAH_LAYERS_CACHE_DIR="/tmp/buildah-cache"
    export STORAGE_DRIVER="overlay"
    
    # Build arguments
    local buildah_args=(
        --format=docker
        --tls-verify=false
        --storage-driver=overlay
        --file Dockerfile-jais2
        --tag "$FULL_IMAGE_NAME"
        --no-cache
    )
    
    # Add container-specific flags
    if [ "$IN_CONTAINER" = true ] && [ "$HAS_PRIVILEGED" = true ]; then
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

# Function to build with Docker
build_with_docker() {
    echo "🐳 Building with Docker..."
    
    # Enable BuildKit
    export DOCKER_BUILDKIT=1
    export BUILDKIT_STEP_LOG_MAX_SIZE=10000000
    export BUILDKIT_STEP_LOG_MAX_SPEED=100
    
    # Build arguments
    local docker_args=(
        --file Dockerfile-jais2
        --tag "$FULL_IMAGE_NAME"
        --build-arg BUILDKIT_INLINE_CACHE=1
        --progress=plain
    )
    
    echo "Running: docker build ${docker_args[*]} ."
    
    if docker build "${docker_args[@]}" .; then
        echo "✅ Docker build completed: $FULL_IMAGE_NAME"
        return 0
    else
        echo "❌ Docker build failed"
        return 1
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

# Function to choose build tool
choose_build_tool() {
    if [ "$FORCE_DOCKER" = true ]; then
        echo "🔧 Forced to use Docker"
        return 1  # Return 1 to indicate Docker
    elif [ "$FORCE_BUILDAH" = true ]; then
        echo "🔧 Forced to use Buildah"
        return 0  # Return 0 to indicate Buildah
    elif [ "$HAS_PRIVILEGED" = true ] && [ "$HAS_BUILDAH" = true ]; then
        echo "🔧 Choosing Buildah (privileged container)"
        return 0  # Return 0 to indicate Buildah
    elif [ "$HAS_DOCKER" = true ]; then
        echo "🔧 Choosing Docker build daemon"
        return 1  # Return 1 to indicate Docker
    elif [ "$HAS_BUILDAH" = true ]; then
        echo "🔧 Choosing Buildah (only option available)"
        return 0  # Return 0 to indicate Buildah
    else
        echo "❌ No build tools available"
        exit 1
    fi
}

# Main execution
main() {
    echo "Starting hybrid build process for JAIS2..."
    echo ""
    
    # Detect environment
    detect_environment
    
    # Validate Dockerfile
    validate_dockerfile
    
    # Choose build tool
    if choose_build_tool; then
        # Use buildah
        USE_BUILDAH=true
        echo "🏗️  Selected build tool: Buildah"
        
        # Test buildah capabilities
        if [ "$IN_CONTAINER" = true ] && [ "$HAS_PRIVILEGED" = false ]; then
            echo "⚠️  Warning: Buildah may fail due to insufficient privileges"
            echo "   Consider using --force-docker if available"
            echo ""
        fi
        
        if build_with_buildah; then
            push_image "buildah"
        else
            echo "❌ Buildah build failed, trying Docker if available..."
            if [ "$HAS_DOCKER" = true ]; then
                setup_docker_in_container
                build_with_docker
                push_image "docker"
            else
                echo "❌ Fallback to Docker not available"
                exit 1
            fi
        fi
    else
        # Use docker
        USE_BUILDAH=false
        echo "🐳 Selected build tool: Docker"
        
        # Install Docker if needed
        install_docker_if_needed
        
        # Setup Docker daemon in container
        setup_docker_in_container
        
        # Build with Docker
        build_with_docker
        push_image "docker"
    fi
    
    # Show final status
    echo ""
    echo "=========================================="
    echo "✅ Hybrid Build Process Complete!"
    echo "=========================================="
    echo ""
    echo "🚀 Built Image: $FULL_IMAGE_NAME"
    echo "🔧 Build Tool Used: $([ "$USE_BUILDAH" = true ] && echo "Buildah" || echo "Docker")"
    echo ""
    echo "📋 Next Steps:"
    echo "  • Test the image: docker run -p 8000:8000 $FULL_IMAGE_NAME"
    echo "  • Check image size: $([ "$USE_BUILDAH" = true ] && echo "buildah images" || echo "docker images")"
    echo "  • Push to registry: Already pushed if authentication was configured"
}

# Handle script interruption
trap 'echo ""; echo "❌ Build interrupted"; exit 1' INT TERM

# Run main function
main "$@"