#!/bin/bash

# Buildah Registry Authentication Helper
# This script helps configure authentication for various container registries

set -e

echo "============================================"
echo "Buildah Registry Authentication Helper"
echo "============================================"

# Function to show help
show_help() {
    echo "Buildah Registry Authentication Helper"
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  login <registry>     Login to a container registry"
    echo "  logout <registry>    Logout from a container registry"
    echo "  status               Show current authentication status"
    echo "  setup-dockerhub      Setup Docker Hub authentication"
    echo "  setup-ghcr          Setup GitHub Container Registry authentication"
    echo "  setup-custom        Setup custom registry authentication"
    echo "  help                 Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 login docker.io              # Login to Docker Hub"
    echo "  $0 setup-ghcr                   # Setup GitHub Container Registry"
    echo "  $0 login myregistry.com:5000    # Login to custom registry"
}

# Function to login to registry
login_registry() {
    if [ -z "$2" ]; then
        echo "Usage: $0 login <registry>"
        echo ""
        echo "Examples:"
        echo "  $0 login docker.io"
        echo "  $0 login ghcr.io"
        echo "  $0 login myregistry.com:5000"
        exit 1
    fi
    
    local registry="$2"
    echo "🔑 Logging into registry: $registry"
    
    # Use buildah to login
    if command -v buildah >/dev/null 2>&1; then
        buildah login --tls-verify=false "$registry"
    elif command -v podman >/dev/null 2>&1; then
        podman login --tls-verify=false "$registry"
    else
        echo "❌ Neither buildah nor podman found. Please install buildah first."
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully logged into $registry"
    else
        echo "❌ Failed to login to $registry"
        exit 1
    fi
}

# Function to logout from registry
logout_registry() {
    if [ -z "$2" ]; then
        echo "Usage: $0 logout <registry>"
        exit 1
    fi
    
    local registry="$2"
    echo "🔓 Logging out from registry: $registry"
    
    if command -v buildah >/dev/null 2>&1; then
        buildah logout "$registry"
    elif command -v podman >/dev/null 2>&1; then
        podman logout "$registry"
    else
        echo "❌ Neither buildah nor podman found"
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully logged out from $registry"
    else
        echo "❌ Failed to logout from $registry"
        exit 1
    fi
}

# Function to show authentication status
show_status() {
    echo "📋 Current Authentication Status:"
    echo ""
    
    # Check for auth files
    local auth_file="$HOME/.config/containers/auth.json"
    
    if [ -f "$auth_file" ]; then
        echo "📄 Auth file found: $auth_file"
        echo "🔍 Configured registries:"
        
        if command -v jq >/dev/null 2>&1; then
            jq -r 'keys[]' "$auth_file" 2>/dev/null | sed 's/^/  • /' || echo "  • Could not parse auth file"
        else
            echo "  • Install jq for detailed registry list"
        fi
    else
        echo "❌ No authentication file found"
        echo "   Expected location: $auth_file"
    fi
    
    echo ""
    echo "🗂️  Container configuration directory:"
    echo "   • Config: $HOME/.config/containers/"
    echo "   • Auth: $HOME/.config/containers/auth.json"
    echo "   • Registries: /etc/containers/registries.conf"
    
    if [ -f "/etc/containers/registries.conf" ]; then
        echo ""
        echo "🔧 Registry configuration:"
        grep -E "^\[|registries\s*=" /etc/containers/registries.conf | head -10
    fi
}

# Function to setup Docker Hub authentication
setup_dockerhub() {
    echo "🐳 Setting up Docker Hub authentication..."
    echo ""
    echo "Docker Hub (docker.io) requires:"
    echo "  • Your Docker Hub username"
    echo "  • Your Docker Hub password or access token"
    echo ""
    echo "⚠️  Recommended: Use an access token instead of your password"
    echo "   Create tokens at: https://hub.docker.com/settings/security"
    echo ""
    
    read -p "Enter your Docker Hub username: " username
    echo ""
    echo "🔑 Enter your Docker Hub password or access token:"
    read -s password
    echo ""
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        echo "❌ Username and password are required"
        exit 1
    fi
    
    # Use buildah to login
    echo "🔐 Authenticating with Docker Hub..."
    echo "$password" | buildah login --username "$username" --password-stdin docker.io
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully authenticated with Docker Hub"
        echo ""
        echo "🚀 You can now push/pull from docker.io"
        echo "   Example: buildah push myimage docker://docker.io/$username/myimage:latest"
    else
        echo "❌ Failed to authenticate with Docker Hub"
        exit 1
    fi
    
    # Clear password from memory
    unset password
}

# Function to setup GitHub Container Registry authentication
setup_ghcr() {
    echo "🐙 Setting up GitHub Container Registry authentication..."
    echo ""
    echo "GitHub Container Registry (ghcr.io) requires:"
    echo "  • Your GitHub username"
    echo "  • A GitHub Personal Access Token (PAT)"
    echo ""
    echo "⚠️  Required PAT scopes:"
    echo "   • write:packages - To push packages"
    echo "   • read:packages - To pull packages"
    echo ""
    echo "📝 Create PAT at: https://github.com/settings/tokens"
    echo ""
    
    read -p "Enter your GitHub username: " username
    echo ""
    echo "🔑 Enter your GitHub Personal Access Token:"
    read -s password
    echo ""
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        echo "❌ Username and token are required"
        exit 1
    fi
    
    # Use buildah to login
    echo "🔐 Authenticating with GitHub Container Registry..."
    echo "$password" | buildah login --username "$username" --password-stdin ghcr.io
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully authenticated with GitHub Container Registry"
        echo ""
        echo "🚀 You can now push/pull from ghcr.io"
        echo "   Example: buildah push myimage docker://ghcr.io/$username/myimage:latest"
    else
        echo "❌ Failed to authenticate with GitHub Container Registry"
        exit 1
    fi
    
    # Clear password from memory
    unset password
}

# Function to setup custom registry authentication
setup_custom() {
    echo "🔧 Setting up custom registry authentication..."
    echo ""
    read -p "Enter registry URL (e.g., myregistry.com:5000): " registry
    read -p "Enter username: " username
    echo ""
    echo "🔑 Enter password:"
    read -s password
    echo ""
    
    if [ -z "$registry" ] || [ -z "$username" ] || [ -z "$password" ]; then
        echo "❌ Registry, username, and password are required"
        exit 1
    fi
    
    # Use buildah to login
    echo "🔐 Authenticating with $registry..."
    echo "$password" | buildah login --username "$username" --password-stdin "$registry"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully authenticated with $registry"
        echo ""
        echo "🚀 You can now push/pull from $registry"
        echo "   Example: buildah push myimage docker://$registry/$username/myimage:latest"
    else
        echo "❌ Failed to authenticate with $registry"
        exit 1
    fi
    
    # Clear password from memory
    unset password
}

# Function to create auth directory structure
setup_auth_directories() {
    echo "📁 Setting up authentication directories..."
    
    local config_dir="$HOME/.config/containers"
    local auth_file="$config_dir/auth.json"
    
    # Create directories
    mkdir -p "$config_dir"
    
    # Create basic auth.json if it doesn't exist
    if [ ! -f "$auth_file" ]; then
        echo "📄 Creating basic authentication configuration..."
        tee "$auth_file" > /dev/null <<'EOF'
{
  "auths": {}
}
EOF
        echo "✅ Created: $auth_file"
    else
        echo "✅ Authentication directory already exists: $config_dir"
    fi
}

# Main execution
main() {
    # Setup directories first
    setup_auth_directories
    
    case "$1" in
        login)
            login_registry "$@"
            ;;
        logout)
            logout_registry "$@"
            ;;
        status)
            show_status
            ;;
        setup-dockerhub)
            setup_dockerhub
            ;;
        setup-ghcr)
            setup_ghcr
            ;;
        setup-custom)
            setup_custom
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Check if buildah is available
if ! command -v buildah >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
    echo "❌ Neither buildah nor podman found"
    echo ""
    echo "To install buildah, run:"
    echo "  sudo ./install-buildah-container.sh"
    exit 1
fi

# Run main function
main "$@"