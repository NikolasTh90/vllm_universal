#!/bin/bash

# Docker Build and Push Script with Performance Optimization
# This script builds and pushes the Dockerimages with optimized settings

set -e

echo "============================================"
echo "Docker Build and Push with Performance Optimization"
echo "============================================"

# Configuration
REGISTRY="${DOCKER_REGISTRY:-nikolasth90/}"
IMAGE_NAME="${IMAGE_NAME:-vllm-universal}"
TAG="${TAG:-latest}"

# Dockerfiles to build
DOCKERFILES=(
    "Dockerfile:standard"
    "Dockerfile-jais2:jais2"
)

# Allow command line override for single Dockerfile build
if [ $# -gt 0 ]; then
    case "$1" in
        "-f"|"--file")
            if [ $# -gt 1 ]; then
                CUSTOM_DOCKERFILE="$2"
                shift 2
            fi
            ;;
        "-t"|"--tag")
            if [ $# -gt 1 ]; then
                CUSTOM_TAG="$2"
                shift 2
            fi
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -f, --file Dockerfile    Specify custom Dockerfile (default: auto-detect)"
            echo "  -t, --tag TAG           Specify custom tag (default: latest)"
            echo "  -jais2                  Build only JAIS2 variant"
            echo "  -standard               Build only standard variant"
            echo "  help, -h, --help        Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  DOCKER_REGISTRY         Registry prefix (default: nikolasth90/)"
            echo "  IMAGE_NAME              Base image name (default: vllm-universal)"
            echo "  TAG                     Tag suffix (default: latest)"
            echo ""
            echo "Examples:"
            echo "  $0                      # Build all variants"
            echo "  $0 -jais2              # Build only JAIS2 variant"
            echo "  $0 -standard           # Build only standard variant"
            echo "  $0 -f Dockerfile-jais2 -t nikolasth90/vllm-universal:jais2"
            echo "  DOCKER_REGISTRY=myreg/ $0  # Build for custom registry"
            exit 0
            ;;
        "-jais2")
            DOCKERFILES=("Dockerfile-jais2:jais2")
            shift
            ;;
        "-standard")
            DOCKERFILES=("Dockerfile:standard")
            shift
            ;;
    esac
    
    # Handle custom Dockerfile and tag
    if [ -n "$CUSTOM_DOCKERFILE" ] && [ -n "$CUSTOM_TAG" ]; then
        echo "Building custom Dockerfile: $CUSTOM_DOCKERFILE with tag: $CUSTOM_TAG"
        
        # Install Docker if needed
        if ! command -v docker >/dev/null 2>&1; then
            echo "Docker not found. Installing..."
            if [ -f "./install-docker-container.sh" ]; then
                sudo ./install-docker-container.sh
            else
                echo "ERROR: install-docker-container.sh not found"
                exit 1
            fi
        fi
        
        # Start Docker if in container
        if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
            echo "Starting Docker daemon in container mode..."
            dockerd --host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2375 &
            sleep 5
            
            for i in {1..30}; do
                if docker version >/dev/null 2>&1; then
                    break
                fi
                sleep 1
            done
        fi
        
        # Enable BuildKit
        export DOCKER_BUILDKIT=1
        export BUILDKIT_STEP_LOG_MAX_SIZE=10000000
        export BUILDKIT_STEP_LOG_MAX_SPEED=100
        
        # Build the custom image
        docker build \
            --file "$CUSTOM_DOCKERFILE" \
            --tag "$CUSTOM_TAG" \
            --build-arg BUILDKIT_INLINE_CACHE=1 \
            --progress=plain \
            .
            
        echo "✅ Build completed: $CUSTOM_TAG"
        
        # Push if registry is detected in tag
        if [[ "$CUSTOM_TAG" == */* ]]; then
            echo "🚀 Pushing to registry..."
            docker push "$CUSTOM_TAG"
            echo "✅ Push completed: $CUSTOM_TAG"
        fi
        
        exit 0
    fi
fi

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not available. Installing Docker for container environment..."
    
    # Check if we're in a container environment
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
        echo "Detected container environment. Using container installation..."
        if [ -f "./install-docker-container.sh" ]; then
            sudo ./install-docker-container.sh
        else
            echo "ERROR: install-docker-container.sh not found"
            exit 1
        fi
    else
        echo "Using standard installation..."
        if [ -f "./install-docker-ubuntu2404.sh" ]; then
            sudo ./install-docker-ubuntu2404.sh
        else
            echo "ERROR: install-docker-ubuntu2404.sh not found"
            exit 1
        fi
    fi
fi

# Start Docker if in container environment
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    echo "Starting Docker daemon in container mode..."
    
    # Create necessary directories
    sudo mkdir -p /var/run /var/lib/docker
    
    # Start Docker daemon with TLS disabled and secure settings
    dockerd \
        --host=unix:///var/run/docker.sock \
        --host=tcp://127.0.0.1:2375 \
        --tls=false \
        --tlsverify=false \
        --storage-driver=overlay2 \
        --exec-root=/var/run/docker \
        --data-root=/var/lib/docker \
        --iptables=false \
        --ip-masq=false \
        --bridge=none \
        --pidfile=/var/run/docker.pid \
        --userland-proxy=false \
        --live-restore \
        --log-level=warn > /dev/null 2>&1 &
    
    DOCKER_PID=$!
    echo "Docker daemon started with PID: $DOCKER_PID"
    
    # Wait for Docker to be ready
    echo "Waiting for Docker to be ready..."
    for i in {1..60}; do
        if docker version >/dev/null 2>&1; then
            echo "✅ Docker is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "⚠️  Still waiting for Docker to start..."
        fi
        sleep 1
    done
    
    # Check if Docker is actually ready
    if ! docker version >/dev/null 2>&1; then
        echo "❌ Docker failed to start properly"
        kill $DOCKER_PID 2>/dev/null
        exit 1
    fi
fi

# Enable BuildKit for performance
export DOCKER_BUILDKIT=1
export BUILDKIT_STEP_LOG_MAX_SIZE=10000000
export BUILDKIT_STEP_LOG_MAX_SPEED=100

echo ""
echo "🔧 Build Configuration:"
echo "  • Registry: ${REGISTRY:-<local>}"
echo "  • Image Name: $IMAGE_NAME"
echo "  • Tag: $TAG"
echo "  • BuildKit: Enabled"
echo ""

# Function to build and push image
build_and_push() {
    local dockerfile=$1
    local variant=$2
    local full_image_name="${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}"
    
    echo "=========================================="
    echo "Building $variant variant from $dockerfile"
    echo "Image: $full_image_name"
    echo "=========================================="
    
    # Build with optimization flags
    docker build \
        --file "$dockerfile" \
        --tag "$full_image_name" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --cache-from "${full_image_name}" \
        --progress=plain \
        .
    
    echo "✅ Build completed: $full_image_name"
    
    # Analyze image if dive is available
    if command -v dive >/dev/null 2>&1; then
        echo "📊 Analyzing image efficiency..."
        dive "$full_image_name" --ci | head -20
    fi
    
    # Push if registry is specified
    if [ -n "$REGISTRY" ]; then
        echo "🚀 Pushing image to registry..."
        docker push "$full_image_name"
        echo "✅ Push completed: $full_image_name"
    else
        echo "ℹ️  No registry specified. Skipping push."
        echo "   To push, set DOCKER_REGISTRY environment variable:"
        echo "   export DOCKER_REGISTRY=your-registry.com/"
    fi
    
    echo ""
}

# Build each Dockerfile variant
for dockerfile_info in "${DOCKERFILES[@]}"; do
    IFS=':' read -r dockerfile variant <<< "$dockerfile_info"
    
    if [ -f "$dockerfile" ]; then
        build_and_push "$dockerfile" "$variant"
    else
        echo "⚠️  Dockerfile not found: $dockerfile"
    fi
done

# Optimize images with DockerSlim if available
if command -v docker-slim >/dev/null 2>&1; then
    echo "🔧 Creating optimized versions with DockerSlim..."
    for dockerfile_info in "${DOCKERFILES[@]}"; do
        IFS=':' read -r dockerfile variant <<< "$dockerfile_info"
        full_image_name="${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}"
        
        if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$full_image_name"; then
            echo "Optimizing $variant variant..."
            docker-slim build "$full_image_name" --tag "${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}-slim"
            echo "✅ Optimized image: ${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}-slim"
        fi
    done
fi

# Display built images
echo ""
echo "=========================================="
echo "📋 Built Images:"
docker images --filter "reference=${REGISTRY}${IMAGE_NAME}*"

# Show image sizes and optimization
echo ""
echo "📊 Image Sizes:"
for dockerfile_info in "${DOCKERFILES[@]}"; do
    IFS=':' read -r dockerfile variant <<< "$dockerfile_info"
    full_image_name="${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}"
    slim_image_name="${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}-slim"
    
    if command -v docker >/dev/null 2>&1; then
        echo "  • $variant:"
        if docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -q "$full_image_name"; then
            echo "    Standard: $(docker images --format "{{.Size}}" "$full_image_name")"
        fi
        if docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -q "$slim_image_name"; then
            echo "    Optimized: $(docker images --format "{{.Size}}" "$slim_image_name")"
        fi
    fi
done

echo ""
echo "=========================================="
echo "✅ Build and Push Complete!"
echo "=========================================="
echo ""
echo "🚀 Ready to use images:"
for dockerfile_info in "${DOCKERFILES[@]}"; do
    IFS=':' read -r dockerfile variant <<< "$dockerfile_info"
    echo "  • ${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}"
done

if command -v docker-slim >/dev/null 2>&1; then
    echo ""
    echo "🔧 Optimized versions:"
    for dockerfile_info in "${DOCKERFILES[@]}"; do
        IFS=':' read -r dockerfile variant <<< "$dockerfile_info"
        echo "  • ${REGISTRY}${IMAGE_NAME}:${variant}-${TAG}-slim"
    done
fi

echo ""
echo "📋 Usage Examples:"
echo "  • Standard variant: docker run -p 8000:8000 ${REGISTRY}${IMAGE_NAME}:standard-${TAG}"
echo "  • JAIS2 variant: docker run -p 8000:8000 ${REGISTRY}${IMAGE_NAME}:jais2-${TAG}"
echo ""
echo "🔧 Environment Variables for customization:"
echo "  • VLLM_MODEL_NAME - Model to serve (default: mistralai/Mistral-7B-Instruct-v0.3)"
echo "  • VLLM_GPU_UTIL - GPU utilization (default: 0.95)"
echo "  • VLLM_MAX_MODEL_LEN - Maximum model length (default: 8192)"
echo ""
echo "✅ All operations completed successfully!"