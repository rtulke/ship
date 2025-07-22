#!/bin/bash
set -euo pipefail

# Release Helper Script
# Automatisiert das Erstellen und Veröffentlichen von Releases

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_NAME="myapp"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

error_exit() {
    log_error "$1"
    exit 1
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        error_exit "Not in a git repository"
    fi
    
    if [[ -n "$(git status --porcelain)" ]]; then
        error_exit "Working directory not clean. Commit your changes first."
    fi
}

# Get current version from git tags
get_current_version() {
    git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
}

# Increment version number
increment_version() {
    local VERSION="$1"
    local PART="$2"
    
    # Remove 'v' prefix if present
    VERSION="${VERSION#v}"
    
    local MAJOR MINOR PATCH
    IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
    
    case "$PART" in
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        patch)
            PATCH=$((PATCH + 1))
            ;;
        *)
            error_exit "Invalid version part: $PART (use: major, minor, patch)"
            ;;
    esac
    
    echo "v${MAJOR}.${MINOR}.${PATCH}"
}

# Create or update update-manifest.yaml
create_update_manifest() {
    local VERSION="$1"
    local DESCRIPTION="$2"
    
    cat > update-manifest.yaml << EOF
# Update Manifest for ${APP_NAME} ${VERSION}
version: "${VERSION#v}"
release_date: "$(date -I)"
description: "${DESCRIPTION}"

# File handling rules
files:
  # Configuration files - preserve user settings
  "config.toml":
    action: "merge_toml"
    merge_strategy: "preserve_user"
    backup: true

  "config/*.toml":
    action: "merge_toml" 
    merge_strategy: "preserve_user"
    backup: true

  "settings.json":
    action: "merge_json"
    merge_strategy: "preserve_user"
    backup: true

  # Application code - always replace
  "src/**/*.py":
    action: "replace"

  "*.py":
    action: "replace"

  "requirements.txt":
    action: "replace"

  # Templates and static files
  "templates/**/*":
    action: "backup_replace"

  "static/**/*":
    action: "replace"

  # Environment files - never touch
  ".env":
    action: "skip"

  ".env.*":
    action: "skip"

  "secrets/*":
    action: "skip"

# Directory preservation
directories:
  # User data - always preserve
  "data":
    preserve: true
    description: "User data directory"

  "images":
    preserve: true
    description: "User uploaded images"

  "uploads":
    preserve: true
    description: "User uploads"

  # Logs - preserve with cleanup
  "logs":
    preserve: true
    cleanup_old: true
    keep_days: 30

  # Cache and temp - can be cleared
  "cache":
    preserve: false

  "tmp":
    preserve: false

# Update hooks
hooks:
  pre_update:
    - "systemctl stop ${APP_NAME}.service || true"
    - "python3 -m ${APP_NAME}.scripts.pre_update_check"

  post_update:
    - "pip install -r requirements.txt"
    - "python3 -m ${APP_NAME}.scripts.migrate"
    - "systemctl start ${APP_NAME}.service"
    - "python3 -m ${APP_NAME}.scripts.health_check"

  rollback:
    - "systemctl stop ${APP_NAME}.service || true"
    - "systemctl start ${APP_NAME}.service"

# Requirements
requirements:
  min_python_version: "3.8"
  min_disk_space_mb: 100
  required_commands:
    - "systemctl"
    - "python3"
    - "pip"

# Rollback configuration
rollback:
  strategy: "full_backup"
  keep_backups: 5
  auto_rollback_on:
    - "health_check_fail"
    - "service_start_fail"

# Post-update tests
post_update_tests:
  - name: "Import test"
    command: "python3 -c 'import ${APP_NAME}; print(\"Import OK\")'"
    timeout: 30

  - name: "Service health"
    command: "curl -f http://localhost:8000/health || python3 -c 'import ${APP_NAME}.health; ${APP_NAME}.health.check()'"
    timeout: 30
    retry_count: 3
    retry_delay: 5
EOF

    log_success "Created update-manifest.yaml for version $VERSION"
}

# Git release workflow
git_release() {
    local VERSION="$1"
    local DESCRIPTION="$2"
    
    log_info "Creating Git release for version $VERSION"
    
    # Create/update manifest
    create_update_manifest "$VERSION" "$description"
    
    # Add manifest to git
    git add update-manifest.yaml
    git commit -m "Add update manifest for $VERSION"
    
    # Create tag
    git tag -a "$VERSION" -m "$DESCRIPTION"
    
    # Push changes and tags
    git push origin main
    git push origin "$VERSION"
    
    log_success "Git release $VERSION created and pushed"
}

# HTTP release workflow  
http_release() {
    local VERSION="$1"
    local DESCRIPTION="$2"
    local RELEASE_DIR="${APP_NAME}-${VERSION#v}"
    
    log_info "Creating HTTP release package for version $VERSION"
    
    # Create release directory
    rm -rf "$RELEASE_DIR"
    mkdir "$RELEASE_DIR"
    
    # Copy application files
    local FILES_TO_COPY=(
        "src"
        "templates"
        "static"
        "config"
        "requirements.txt"
        "*.py"
        "README.md"
    )
    
    for PATTERN in "${FILES_TO_COPY[@]}"; do
        if ls $PATTERN &>/dev/null; then
            cp -r $PATTERN "$RELEASE_DIR/" 2>/dev/null || true
        fi
    done
    
    # Create manifest in release directory
    create_update_manifest "$VERSION" "$DESCRIPTION"
    cp update-manifest.yaml "$RELEASE_DIR/"
    
    # Create archive
    tar czf "${RELEASE_DIR}.tar.gz" "$RELEASE_DIR"
    
    # Generate checksum
    sha256sum "${RELEASE_DIR}.tar.gz" > "${RELEASE_DIR}.tar.gz.sha256"
    
    log_success "Release package created: ${RELEASE_DIR}.tar.gz"
    log_info "Checksum: $(cat ${RELEASE_DIR}.tar.gz.sha256)"
    
    # Cleanup
    rm -rf "$RELEASE_DIR"
    
    # Show upload instructions
    echo
    log_info "Upload instructions:"
    echo "1. Upload ${RELEASE_DIR}.tar.gz to your HTTP server"
    echo "2. Update your updater.toml with the new URL"
    echo "3. Optionally upload the checksum file for integrity verification"
}

# SFTP release workflow
sftp_release() {
    local VERSION="$1"
    local DESCRIPTION="$2"
    local SFTP_HOST="$3"
    local SFTP_USER="$4"
    local SFTP_PATH="$5"
    
    # Create HTTP release first
    http_release "$VERSION" "$DESCRIPTION"
    
    local RELEASE_FILE="${APP_NAME}-${VERSION#v}.tar.gz"
    
    log_info "Uploading $RELEASE_FILE to SFTP server"
    
    # Upload via SFTP
    sftp "${SFTP_USER}@${SFTP_HOST}" << EOF
put ${RELEASE_FILE} ${SFTP_PATH}/
put ${RELEASE_FILE}.sha256 ${SFTP_PATH}/
quit
EOF

    log_success "Uploaded to SFTP: ${SFTP_USER}@${SFTP_HOST}:${SFTP_PATH}/${RELEASE_FILE}"
    
    # Cleanup local files
    rm -f "$RELEASE_FILE" "${RELEASE_FILE}.sha256"
}

# Interactive release creation
interactive_release() {
    echo "=== ${APP_NAME} Release Creator ==="
    echo
    
    # Get current version
    local CURRENT_VERSION
    CURRENT_VERSION=$(get_current_version)
    log_info "Current version: $CURRENT_VERSION"
    
    # Ask for version increment
    echo
    echo "Select version increment:"
    echo "1) Patch (bug fixes)     - ${CURRENT_VERSION} -> $(increment_version "$CURRENT_VERSION" patch)"
    echo "2) Minor (new features)  - ${CURRENT_VERSION} -> $(increment_version "$CURRENT_VERSION" minor)" 
    echo "3) Major (breaking)      - ${CURRENT_VERSION} -> $(increment_version "$CURRENT_VERSION" major)"
    echo "4) Custom version"
    echo
    
    local CHOICE NEW_VERSION
    read -p "Choice [1-4]: " CHOICE
    
    case "$CHOICE" in
        1) NEW_VERSION=$(increment_version "$CURRENT_VERSION" patch) ;;
        2) NEW_VERSION=$(increment_version "$CURRENT_VERSION" minor) ;;
        3) NEW_VERSION=$(increment_version "$CURRENT_VERSION" major) ;;
        4) 
            read -p "Enter version (e.g., v1.2.3): " NEW_VERSION
            if [[ ! "$NEW_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                error_exit "Invalid version format. Use v1.2.3"
            fi
            ;;
        *) error_exit "Invalid choice" ;;
    esac
    
    # Get release description
    echo
    read -p "Release description: " DESCRIPTION
    if [[ -z "$DESCRIPTION" ]]; then
        DESCRIPTION="Release $NEW_VERSION"
    fi
    
    # Choose release method
    echo
    echo "Select release method:"
    echo "1) Git (recommended)"
    echo "2) HTTP package"
    echo "3) SFTP upload"
    echo
    
    read -p "Choice [1-3]: " METHOD
    
    case "$METHOD" in
        1) git_release "$NEW_VERSION" "$DESCRIPTION" ;;
        2) http_release "$NEW_VERSION" "$DESCRIPTION" ;;
        3) 
            read -p "SFTP Host: " SFTP_HOST
            read -p "SFTP User: " SFTP_USER
            read -p "SFTP Path: " SFTP_PATH
            sftp_release "$NEW_VERSION" "$DESCRIPTION" "$SFTP_HOST" "$SFTP_USER" "$SFTP_PATH"
            ;;
        *) error_exit "Invalid choice" ;;
    esac
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

Commands:
    interactive          Interactive release creation
    git VERSION DESC     Create Git release
    http VERSION DESC    Create HTTP package
    sftp VERSION DESC    Create and upload SFTP package
    manifest VERSION     Create manifest only

Options:
    -h, --help          Show this help

Examples:
    $0 interactive
    $0 git v1.2.3 "Bug fixes and improvements"  
    $0 http v1.2.3 "New features"
    $0 sftp v1.2.3 "Hotfix" host user /path

EOF
}

# Main function
main() {
    # Check requirements
    check_git_repo
    
    case "${1:-}" in
        interactive|"")
            interactive_release
            ;;
        git)
            [[ $# -ge 3 ]] || error_exit "Usage: $0 git VERSION DESCRIPTION"
            git_release "$2" "$3"
            ;;
        http) 
            [[ $# -ge 3 ]] || error_exit "Usage: $0 http VERSION DESCRIPTION"
            http_release "$2" "$3"
            ;;
        sftp)
            [[ $# -ge 6 ]] || error_exit "Usage: $0 sftp VERSION DESCRIPTION HOST USER PATH"
            sftp_release "$2" "$3" "$4" "$5" "$6"
            ;;
        manifest)
            [[ $# -ge 2 ]] || error_exit "Usage: $0 manifest VERSION"
            create_update_manifest "$2" "Manual manifest creation"
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
