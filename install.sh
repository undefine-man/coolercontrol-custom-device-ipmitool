#!/bin/sh
set -e

# Configuration
REPO_URL="https://gitlab.com/coolercontrol/cc-plugin-custom-device"
PLUGINS_DIR="/etc/coolercontrol/plugins"
SERVICE_ID="custom-device"
EXECUTABLE="custom-device"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
    exit 1
}

# Check for required tools
check_requirements() {
    if ! command -v curl >/dev/null 2>&1; then
        error "curl is required but not installed."
    fi
}

# Detect system architecture
get_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            ;;
    esac
}

# Get the latest release tag from GitLab
get_latest_version() {
    curl -s "${REPO_URL}/-/tags?format=atom" | grep -oP '(?<=<title>)[^<]+' | head -2 | tail -1
}

# Download a file from the repository
download_file() {
    local file_path="$1"
    local dest="$2"
    local version="$3"
    
    info "Downloading ${file_path}..."
    curl -fsSL "${REPO_URL}/-/raw/${version}/${file_path}" -o "${dest}"
}

# Download the release binary
download_binary() {
    local version="$1"
    local dest="$2"
    local arch="$3"
    
    info "Downloading binary for ${version} (${arch})..."
    curl -fsSL "${REPO_URL}/-/releases/${version}/downloads/${EXECUTABLE}-linux-${arch}" -o "${dest}"
}

main() {
    info "CoolerControl Custom Device Plugin Installer"
    echo ""
    
    check_requirements
    
    # Detect architecture
    ARCH=$(get_arch)
    info "Detected architecture: ${ARCH}"
    
    # Get version (use argument or fetch latest)
    VERSION="${1:-}"
    if [ -z "$VERSION" ]; then
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
        if [ -z "$VERSION" ]; then
            error "Could not determine latest version. Please specify a version as an argument."
        fi
    fi
    info "Installing version: ${VERSION}"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf ${TEMP_DIR}' EXIT
    
    # Download files
    download_binary "${VERSION}" "${TEMP_DIR}/${EXECUTABLE}" "${ARCH}"
    download_file "plugin-files/manifest.toml" "${TEMP_DIR}/manifest.toml" "${VERSION}"
    download_file "plugin-files/ui/index.html" "${TEMP_DIR}/index.html" "${VERSION}"

    # Install files
    info "Installing files to ${PLUGINS_DIR}/${SERVICE_ID}..."
    mkdir -p "${PLUGINS_DIR}/${SERVICE_ID}/ui"
    install -m755 "${TEMP_DIR}/${EXECUTABLE}" "${PLUGINS_DIR}/${SERVICE_ID}/"
    if [ -f "${PLUGINS_DIR}/${SERVICE_ID}/manifest.toml" ]; then
        warn "manifest.toml already exists, saving existing file as manifest.toml.old"
        mv "${PLUGINS_DIR}/${SERVICE_ID}/manifest.toml" "${PLUGINS_DIR}/${SERVICE_ID}/manifest.toml.old"
    fi
    install -m644 "${TEMP_DIR}/manifest.toml" "${PLUGINS_DIR}/${SERVICE_ID}/"
    install -m644 "${TEMP_DIR}/index.html" "${PLUGINS_DIR}/${SERVICE_ID}/ui/"

    echo ""
    info "Installation complete!"
    echo ""
    warn "Remember to restart the CoolerControl daemon:"
    echo "  systemctl restart coolercontrold"
    echo ""
}

main "$@"
