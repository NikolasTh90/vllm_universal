#!/bin/bash

# Test Buildah Setup Script
# Validates that all components are ready for building JAIS2 with buildah

set -e

echo "============================================"
echo "Testing Buildah Setup for JAIS2"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    if [ "$status" = "PASS" ]; then
        echo -e "✅ ${GREEN}$message${NC}"
    elif [ "$status" = "WARN" ]; then
        echo -e "⚠️  ${YELLOW}$message${NC}"
    else
        echo -e "❌ ${RED}$message${NC}"
    fi
}

# Function to run test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local required="${3:-true}"
    
    echo ""
    echo "🔍 Testing: $test_name"
    echo "Command: $test_command"
    
    if eval "$test_command" >/dev/null 2>&1; then
        print_status "PASS" "$test_name - Available"
        return 0
    else
        if [ "$required" = "true" ]; then
            print_status "FAIL" "$test_name - Required but not found"
            return 1
        else
            print_status "WARN" "$test_name - Optional but not found"
            return 0
        fi
    fi
}

# Function to check file existence
check_file() {
    local file_path="$1"
    local description="$2"
    local required="${3:-true}"
    
    echo ""
    echo "🔍 Checking file: $file_path"
    
    if [ -f "$file_path" ]; then
        print_status "PASS" "$description - Found"
        return 0
    else
        if [ "$required" = "true" ]; then
            print_status "FAIL" "$description - Required but missing"
            return 1
        else
            print_status "WARN" "$description - Optional but missing"
            return 0
        fi
    fi
}

# Function to check directory structure
check_directory() {
    local dir_path="$1"
    local description="$2"
    local required="${3:-true}"
    
    echo ""
    echo "🔍 Checking directory: $dir_path"
    
    if [ -d "$dir_path" ]; then
        print_status "PASS" "$description - Found"
        return 0
    else
        if [ "$required" = "true" ]; then
            print_status "FAIL" "$description - Required but missing"
            return 1
        else
            print_status "WARN" "$description - Optional but missing"
            return 0
        fi
    fi
}

# Run all tests
echo "Starting buildah setup validation..."
echo ""

# Test 1: Check for container environment indicators
echo "🐳 Container Environment Detection"
if [ -f /.dockerenv ]; then
    print_status "PASS" "Running in Docker container (.dockerenv found)"
elif [ -f /run/.containerenv ]; then
    print_status "PASS" "Running in container (.containerenv found)"
elif [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    print_status "PASS" "Running in Kubernetes pod"
else
    print_status "WARN" "Not in detected container environment"
fi

# Test 2: Check basic tools
run_test "curl" "command -v curl" "true"
run_test "wget" "command -v wget" "true"
run_test "tar" "command -v tar" "true"

# Test 3: Check container tools
run_test "buildah" "command -v buildah" "true"
run_test "skopeo" "command -v skopeo" "false"  # Optional
run_test "podman" "command -v podman" "false"  # Optional

# Test 4: Check package manager
run_test "apt-get" "command -v apt-get" "false"  # Optional, depends on distro

# Test 5: Check our scripts
check_file "./install-buildah-container.sh" "Container buildah installation script" "true"
check_file "./install-buildah-ubuntu.sh" "Ubuntu buildah installation script" "true"
check_file "./build-jais2-with-buildah.sh" "JAIS2 build script" "true"
check_file "./buildah-registry-auth.sh" "Registry authentication script" "true"
check_file "./Dockerfile-jais2" "JAIS2 Dockerfile" "true"
check_file "./BUILDAH-QUICK-START.md" "Documentation" "true"

# Test 6: Check script permissions
echo ""
echo "🔍 Checking script permissions"
for script in install-buildah-container.sh install-buildah-ubuntu.sh build-jais2-with-buildah.sh buildah-registry-auth.sh; do
    if [ -x "$script" ]; then
        print_status "PASS" "$script is executable"
    else
        print_status "WARN" "$script is not executable - run 'chmod +x $script'"
    fi
done

# Test 7: Check container configuration directories
check_directory "/etc/containers" "Containers configuration directory" "false"

# Test 8: If buildah exists, test its configuration
if command -v buildah >/dev/null 2>&1; then
    echo ""
    echo "🔍 Testing buildah configuration"
    
    if buildah --version >/dev/null 2>&1; then
        echo "Buildah version: $(buildah --version)"
        print_status "PASS" "Buildah is functional"
    else
        print_status "FAIL" "Buildah found but not functional"
    fi
    
    # Test buildah can list images (even if empty)
    if buildah images >/dev/null 2>&1; then
        print_status "PASS" "Buildah can communicate with storage"
    else
        print_status "WARN" "Buildah storage communication issue"
    fi
else
    print_status "WARN" "Skipping buildah configuration tests - buildah not installed"
fi

# Test 9: Check authentication setup
echo ""
echo "🔍 Checking authentication setup"
auth_file="$HOME/.config/containers/auth.json"
if [ -f "$auth_file" ]; then
    print_status "PASS" "Authentication file exists"
else
    print_status "WARN" "Authentication file not found - run registry setup"
fi

# Test 10: Check environment variables
echo ""
echo "🔍 Checking environment variables"
echo "DOCKER_REGISTRY: ${DOCKER_REGISTRY:-<not set>}"
echo "IMAGE_NAME: ${IMAGE_NAME:-<not set>}"
echo "TAG: ${TAG:-<not set>}"

# Summary
echo ""
echo "============================================"
echo "📋 Test Summary"
echo "============================================"
echo ""

# Count passes/fails
total_tests=0
failed_tests=0

# Simple summary based on what we found
if command -v buildah >/dev/null 2>&1; then
    print_status "PASS" "Buildah is available"
else
    print_status "WARN" "Buildah not installed - run 'sudo ./install-buildah-container.sh'"
    ((failed_tests++))
fi

if [ -f "./Dockerfile-jais2" ]; then
    print_status "PASS" "Dockerfile-jais2 exists"
else
    print_status "FAIL" "Dockerfile-jais2 missing"
    ((failed_tests++))
fi

if [ -x "./build-jais2-with-buildah.sh" ]; then
    print_status "PASS" "Build script is ready"
else
    print_status "WARN" "Build script needs permissions - run 'chmod +x build-jais2-with-buildah.sh'"
fi

echo ""
if [ $failed_tests -eq 0 ]; then
    echo "🎉 All critical tests passed! You're ready to build JAIS2 with buildah."
    echo ""
    echo "🚀 Next steps:"
    echo "1. Install buildah:"
    echo "   • For Ubuntu 24.04: sudo ./install-buildah-ubuntu.sh"
    echo "   • For containers: sudo ./install-buildah-container.sh"
    echo "2. Setup authentication: ./buildah-registry-auth.sh setup-dockerhub"
    echo "3. Build the image: ./build-jais2-with-buildah.sh"
else
    echo "⚠️  Some critical components are missing. Please address the issues above."
    echo ""
    echo "🔧 To fix common issues:"
    echo "1. Install buildah:"
    echo "   • For Ubuntu 24.04: sudo ./install-buildah-ubuntu.sh"
    echo "   • For containers: sudo ./install-buildah-container.sh"
    echo "2. Make scripts executable: chmod +x *.sh"
    echo "3. Ensure Dockerfile-jais2 exists"
fi

echo ""
echo "📚 For detailed instructions, see: BUILDAH-QUICK-START.md"
echo ""