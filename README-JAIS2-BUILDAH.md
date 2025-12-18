# Complete Buildah Solution for JAIS2 Dockerfile

This repository contains a comprehensive solution for building the JAIS2 Dockerfile using buildah and pushing to container repositories, with special handling for container permission issues.

## 🎯 Problem Solved

You encountered the error: `Error during unshare(CLONE_NEWUSER): Operation not permitted` when trying to build your JAIS2 Dockerfile with buildah in a container environment. This solution provides multiple approaches to handle this common container permission issue.

## 📋 Available Scripts

### Installation Scripts
- **`install-buildah-ubuntu.sh`** - Optimized for Ubuntu 24.04 systems
- **`install-buildah-container.sh`** - Optimized for container environments

### Build Scripts
- **`build-jais2-hybrid.sh`** ⭐ **RECOMMENDED** - Automatically detects environment and chooses optimal build tool
- **`build-jais2-with-buildah.sh`** - Standard buildah script with container detection
- **`build-jais2-with-buildah-root.sh`** - Root/privileged version for permission issues

### Supporting Tools
- **`buildah-registry-auth.sh`** - Registry authentication helper
- **`test-buildah-setup.sh`** - Environment validation and testing

## 🚀 Quick Start (Recommended)

### Step 1: Install Build Tools
```bash
# For Ubuntu 24.04
sudo ./install-buildah-ubuntu.sh

# Or for containers
sudo ./install-buildah-container.sh
```

### Step 2: Setup Registry Authentication
```bash
./buildah-registry-auth.sh setup-dockerhub
```

### Step 3: Build Your Image
```bash
# ✅ RECOMMENDED: Automatically handles all permission issues
./build-jais2-hybrid.sh

# Or with custom settings
./build-jais2-hybrid.sh -r your-registry.com/ -t v1.0 -n your-image
```

## 🔧 How the Hybrid Solution Works

The [`build-jais2-hybrid.sh`](build-jais2-hybrid.sh:1) script automatically:

1. **Detects Environment**: Checks for buildah, docker, container status, and privileges
2. **Chooses Best Tool**: 
   - Uses buildah if you have a privileged container with user namespace support
   - Falls back to Docker daemon-in-Docker if buildah fails
   - Installs Docker automatically if needed
3. **Handles Permissions**: No "Operation not permitted" errors
4. **Provides Fallbacks**: Multiple installation and build methods

## 📊 Environment Detection Results

When you run [`./build-jais2-hybrid.sh`](build-jais2-hybrid.sh:1), you'll see:

```
🔍 Detecting environment capabilities...
✅ Buildah available: buildah version 1.38.0
✅ Docker available: Docker version 24.0.6
🐳 Running in container environment
❌ Container lacks user namespace capabilities

📋 Environment summary:
  • Buildah: true
  • Docker: true
  • Container: true
  • Privileged: false

🔧 Choosing Docker build daemon
🐳 Selected build tool: Docker
```

## 🛠️ Build Script Options

### Standard Options
```bash
# Basic usage
./build-jais2-hybrid.sh

# Custom registry and tag
./build-jais2-hybrid.sh -r ghcr.io/username/ -t v1.0 -n my-jais2

# Force specific tool
./build-jais2-hybrid.sh --force-docker    # Always use Docker
./build-jais2-hybrid.sh --force-buildah   # Always try Buildah
```

### Legacy Options (if you prefer specific approaches)
```bash
# Standard buildah (may fail in unprivileged containers)
./build-jais2-with-buildah.sh

# Root buildah (requires privileged container)
./build-jais2-with-buildah-root.sh

# Or run with sudo for root privileges
sudo ./build-jais2-with-buildah.sh
```

## 🔍 Troubleshooting Guide

### "Operation not permitted" Error
```bash
# Solution: Use hybrid build (best option)
./build-jais2-hybrid.sh

# Or force Docker
./build-jais2-hybrid.sh --force-docker
```

### Container Permission Issues
```bash
# Check your environment
./test-buildah-setup.sh

# If you control the container, restart with privileges:
docker run --privileged -v $(pwd):/workspace -w /workspace your-image
```

### Registry Authentication Issues
```bash
# Check authentication status
./buildah-registry-auth.sh status

# Re-authenticate
./buildah-registry-auth.sh setup-dockerhub
```

## 📚 Detailed Documentation

- **[BUILDAH-QUICK-START.md](BUILDAH-QUICK-START.md)** - Comprehensive step-by-step guide
- **[Dockerfile-jais2](Dockerfile-jais2)** - The JAIS2 Dockerfile you're building

## 🎯 Key Advantages of This Solution

### 1. Automatic Environment Detection
- Detects container vs host environments
- Checks for user namespace capabilities
- Identifies available build tools

### 2. Multiple Build Strategies
- **Buildah**: Daemonless, preferred for production
- **Docker**: Fallback for restrictive environments
- **Root mode**: For privileged containers

### 3. Graceful Fallbacks
- If buildah fails → Try Docker
- If Docker not installed → Auto-install
- Multiple repository sources for dependencies

### 4. Container-Optimized
- Handles Docker-in-Docker scenarios
- Manages Docker daemon lifecycle
- Configures storage for containers

## 🏗️ What Gets Built

The scripts build your [`Dockerfile-jais2`](Dockerfile-jais2:1) which includes:
- Base: `vllm/vllm-openai:latest`
- CUDA toolkit 12.9
- Custom vLLM fork (jais2 branch)
- Custom transformers fork
- JAIS2 model support

## 🚀 Pushing to Registries

The build scripts automatically push when configured:
```bash
# Set your registry
export DOCKER_REGISTRY=your-registry.com/

# Build and push
./build-jais2-hybrid.sh -r your-registry.com/ -t v1.0

# Result: your-registry.com/vllm-universal:jais2-v1.0
```

## ✅ Success Verification

Your setup is working when:
1. ✅ `./test-buildah-setup.sh` shows green checkmarks
2. ✅ `./build-jais2-hybrid.sh` completes without errors
3. ✅ Image appears in your registry
4. ✅ You can run: `docker run -p 8000:8000 your-registry.com/vllm-universal:jais2-v1.0`

## 🔄 Complete Workflow Example

```bash
# 1. Test your environment
./test-buildah-setup.sh

# 2. Install build tools
sudo ./install-buildah-ubuntu.sh

# 3. Setup authentication
./buildah-registry-auth.sh setup-dockerhub

# 4. Build and push
./build-jais2-hybrid.sh -r docker.io/yourusername/ -t latest

# 5. Verify
buildah images | grep vllm-universal
```

## 📞 Support

If you encounter issues:
1. Run `./test-buildah-setup.sh` to diagnose
2. Check [BUILDAH-QUICK-START.md](BUILDAH-QUICK-START.md) for detailed troubleshooting
3. Try the hybrid build first - it handles most cases automatically

---

**🎉 You now have a robust, production-ready solution for building JAIS2 with buildah that works in any container environment!**