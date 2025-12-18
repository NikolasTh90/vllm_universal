# Buildah Quick Start Guide for JAIS2 Dockerfile

This guide shows you how to use buildah to build the JAIS2 Dockerfile and push it to a repository from within a Docker container.

## 🚀 Quick Start

### 1. Install Buildah

```bash
# Install buildah in your container environment
sudo ./install-buildah-container.sh
```

### 2. Setup Registry Authentication

```bash
# For Docker Hub
./buildah-registry-auth.sh setup-dockerhub

# Or for GitHub Container Registry
./buildah-registry-auth.sh setup-ghcr

# Or for custom registry
./buildah-registry-auth.sh setup-custom
```

### 3. Build the JAIS2 Image

```bash
# Build with default settings (docker.io/nikolasth90/vllm-universal:jais2-latest)
./build-jais2-with-buildah.sh

# Or with custom registry and tag
./build-jais2-with-buildah.sh -r myregistry.com/ -t v1.0 -n myjais-image
```

## 📋 Detailed Instructions

### Prerequisites

- You're inside a Docker container with appropriate privileges
- The `Dockerfile-jais2` exists in the current directory
- Network access to download packages and push to registry

### Step 1: Install Buildah

The installation script will:
- Install buildah and dependencies
- Configure containers storage
- Set up registry configurations
- Create helper scripts

```bash
sudo ./install-buildah-container.sh
```

**What this does:**
- Downloads and installs buildah (v1.38.0)
- Installs skopeo for registry operations
- Creates `/etc/containers/` configuration
- Sets up overlay storage driver
- Creates helper scripts in `/usr/local/bin/`

### Step 2: Configure Registry Authentication

Choose your registry:

#### Docker Hub
```bash
./buildah-registry-auth.sh setup-dockerhub
```
- Prompts for Docker Hub username
- Prompts for password or access token (recommended)
- Saves authentication credentials

#### GitHub Container Registry
```bash
./buildah-registry-auth.sh setup-ghcr
```
- Prompts for GitHub username
- Prompts for Personal Access Token (PAT)
- Requires PAT with `write:packages` and `read:packages` scopes

#### Custom Registry
```bash
./buildah-registry-auth.sh setup-custom
```
- Prompts for registry URL (e.g., `myregistry.com:5000`)
- Prompts for username and password

**Check authentication status:**
```bash
./buildah-registry-auth.sh status
```

### Step 3. Build the JAIS2 Image

#### Basic Build
```bash
./build-jais2-with-buildah.sh
```

This will:
- Build from `Dockerfile-jais2`
- Tag as `docker.io/nikolasth90/vllm-universal:jais2-latest`
- Push to registry if authenticated

#### Custom Build
```bash
./build-jais2-with-buildah.sh \
  -r ghcr.io/yourusername/ \
  -t v1.0 \
  -n vllm-jais2
```

**Options:**
- `-r, --registry`: Registry prefix (default: `docker.io/nikolasth90/`)
- `-t, --tag`: Tag suffix (default: `latest`)
- `-n, --name`: Image name (default: `vllm-universal`)

## 🔧 Advanced Usage

### Manual Buildah Commands

If you prefer to use buildah directly:

```bash
# Configure environment
export BUILDAH_ISOLATION=chroot
export BUILDAH_FORMAT=docker
export STORAGE_DRIVER=overlay

# Build the image
buildah bud \
  --format=docker \
  --file Dockerfile-jais2 \
  --tag myimage:jais2 \
  .

# Push to registry
buildah push myimage:jais2 docker://docker.io/username/myimage:jais2
```

### Check Registry Authentication

```bash
# Check current authentication
./buildah-registry-auth.sh status

# Login manually
./buildah-registry-auth.sh login docker.io

# Logout
./buildah-registry-auth.sh logout docker.io
```

### List and Inspect Images

```bash
# List all images
buildah images

# Inspect specific image
buildah inspect docker.io/username/vllm-universal:jais2-latest

# Remove image
buildah rmi docker.io/username/vllm-universal:jais2-latest
```

## 🐳 Running the Built Image

### With Podman (if available)
```bash
# Pull and run
podman run -p 8000:8000 docker.io/username/vllm-universal:jais2-latest

# With GPU support
podman run --device nvidia.com/gpu=all -p 8000:8000 docker.io/username/vllm-universal:jais2-latest
```

### With Docker (if available)
```bash
# Pull and run
docker run -p 8000:8000 docker.io/username/vllm-universal:jais2-latest

# With GPU support
docker run --gpus all -p 8000:8000 docker.io/username/vllm-universal:jais2-latest
```

### Save as Tar File
```bash
# Save to tar file
buildah push docker.io/username/vllm-universal:jais2-latest docker-archive:/tmp/jais2-image.tar

# Load from tar file
buildah pull docker-archive:/tmp/jais2-image.tar
```

## 🔍 Troubleshooting

### Common Issues

1. **Buildah not found**
   ```bash
   sudo ./install-buildah-container.sh
   ```

2. **Permission denied**
   ```bash
   chmod +x *.sh
   sudo ./install-buildah-container.sh
   ```

3. **Authentication failed**
   ```bash
   ./buildah-registry-auth.sh status
   ./buildah-registry-auth.sh login docker.io
   ```

4. **Build failed - missing dependencies**
   - Ensure the base image `vllm/vllm-openai:latest` is available
   - Check network connectivity for git operations
   - Verify CUDA toolkit availability

5. **Push failed - registry issues**
   ```bash
   # Check authentication
   ./buildah-registry-auth.sh status
   
   # Check registry name
   echo "Registry: $DOCKER_REGISTRY"
   
   # Test connectivity
   ping -c 3 docker.io
   ```

### Debug Mode

Enable verbose logging:
```bash
export BUILDAH_LOG_LEVEL=debug
./build-jais2-with-buildah.sh
```

### Container Environment Issues

If you're in a container without sufficient privileges, you may need to run with additional flags:
```bash
# When starting your container
docker run --privileged -v $(pwd):/workspace -w /workspace your-image

# Or with specific capabilities
docker run --cap-add=SYS_ADMIN --device /dev/fuse \
  -v $(pwd):/workspace -w /workspace your-image
```

## 📚 Environment Variables for JAIS2

The JAIS2 image supports these environment variables:

```bash
# Model configuration
VLLM_MODEL_NAME=jais-13b-chat
VLLM_GPU_UTIL=0.95
VLLM_MAX_MODEL_LEN=8192

# API configuration
API_HOST=0.0.0.0
API_PORT=8000
```

Example usage:
```bash
podman run -p 8000:8000 \
  -e VLLM_MODEL_NAME=jais-13b-chat \
  -e VLLM_GPU_UTIL=0.95 \
  docker.io/username/vllm-universal:jais2-latest
```

## 🔄 Workflow Example

Complete workflow from scratch:

```bash
# 1. Install buildah
sudo ./install-buildah-container.sh

# 2. Setup Docker Hub authentication
./buildah-registry-auth.sh setup-dockerhub

# 3. Build JAIS2 image
./build-jais2-with-buildah.sh -r docker.io/yourusername/ -t v1.0

# 4. Verify the image
buildah images | grep vllm-universal

# 5. Test run (if you have podman)
podman run -p 8000:8000 docker.io/yourusername/vllm-universal:jais2-v1.0
```

## 📖 Additional Resources

- [Buildah Documentation](https://buildah.io/)
- [Podman Documentation](https://podman.io/)
- [JAIS Model Information](https://github.com/inceptionai-abudhabi/vllm/tree/jais2)
- [Container Registries Comparison](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

## ✅ Success Metrics

Your setup is working if:

1. ✅ `buildah --version` shows version information
2. ✅ `./buildah-registry-auth.sh status` shows registry authentication
3. ✅ `./build-jais2-with-buildah.sh` completes without errors
4. ✅ `buildah images` shows your built image
5. ✅ Image appears in your container registry web interface

Once all these are working, you've successfully built your JAIS2 Dockerfile with buildah and pushed it to a repository!