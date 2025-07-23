#!/bin/bash
set -euo pipefail

# Ship Application Updater Installation Script
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly UPDATER_USER="ship"
readonly INSTALL_DIR="/opt/ship"
readonly CONFIG_DIR="/etc/ship"
readonly DATA_DIR="/var/lib/ship"
readonly LOG_FILE="/var/log/ship-install.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log_error "Installation failed: $1"
    exit 1
}

# Cleanup function
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}

trap cleanup EXIT

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    local REQUIRED_COMMANDS=("python3" "git" "systemctl")
    local MISSING_COMMANDS=()
    
    for CMD in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "${CMD}" &> /dev/null; then
            MISSING_COMMANDS+=("${CMD}")
        fi
    done
    
    if [[ ${#MISSING_COMMANDS[@]} -ne 0 ]]; then
        error_exit "Missing required commands: ${MISSING_COMMANDS[*]}"
    fi
    
    # Check Python version
    local PYTHON_VERSION
    PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    if [[ $(echo "${PYTHON_VERSION} < 3.8" | bc -l) -eq 1 ]]; then
        error_exit "Python 3.8 or higher required, found ${PYTHON_VERSION}"
    fi
    
    log_success "System requirements satisfied"
}

# Create ship user and directories
setup_user_and_directories() {
    log_info "Setting up user and directories..."
    
    # Create ship user if not exists
    if ! id "${UPDATER_USER}" &> /dev/null; then
        useradd -r -s /bin/false -d "${DATA_DIR}" -c "Ship Application Updater" "${UPDATER_USER}"
        log_success "Created user: ${UPDATER_USER}"
    else
        log_info "User ${UPDATER_USER} already exists"
    fi
    
    # Create directories
    local DIRECTORIES=(
        "${INSTALL_DIR}"
        "${CONFIG_DIR}"
        "${DATA_DIR}"
        "/var/log"
    )
    
    for DIR in "${DIRECTORIES[@]}"; do
        if [[ ! -d "${DIR}" ]]; then
            mkdir -p "${DIR}"
            log_success "Created directory: ${DIR}"
        fi
    done
    
    # Set ownership
    chown -R "${UPDATER_USER}:${UPDATER_USER}" "${DATA_DIR}"
    chown -R root:root "${INSTALL_DIR}" "${CONFIG_DIR}"
    
    log_success "User and directories setup complete"
}

# Install Python dependencies
setup_python_environment() {
    log_info "Setting up Python virtual environment..."
    
    cd "${INSTALL_DIR}"
    
    # Create virtual environment
    if [[ ! -d "venv" ]]; then
        python3 -m venv venv
        log_success "Created Python virtual environment"
    fi
    
    # Activate and install dependencies
    # shellcheck source=/dev/null
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install requirements
    if [[ -f "${SCRIPT_DIR}/requirements.txt" ]]; then
        pip install -r "${SCRIPT_DIR}/requirements.txt"
        log_success "Installed Python dependencies"
    else
        log_warning "requirements.txt not found, installing basic dependencies"
        pip install requests paramiko tomli
    fi
    
    deactivate
}

# Install application files
install_application() {
    log_info "Installing application files..."
    
    # Copy main script
    if [[ -f "${SCRIPT_DIR}/ship.py" ]]; then
        cp "${SCRIPT_DIR}/ship.py" "${INSTALL_DIR}/"
        chmod +x "${INSTALL_DIR}/ship.py"
        log_success "Installed ship.py"
    else
        error_exit "ship.py not found in ${SCRIPT_DIR}"
    fi
    
    # Copy configuration template
    if [[ -f "${SCRIPT_DIR}/ship.toml" ]]; then
        if [[ ! -f "${CONFIG_DIR}/ship.toml" ]]; then
            cp "${SCRIPT_DIR}/ship.toml" "${CONFIG_DIR}/"
            chown "${UPDATER_USER}:${UPDATER_USER}" "${CONFIG_DIR}/ship.toml"
            chmod 600 "${CONFIG_DIR}/ship.toml"
            log_success "Installed configuration template"
        else
            log_warning "Configuration file already exists, skipping"
        fi
    fi
    
    # Set permissions
    chown -R root:root "${INSTALL_DIR}"
    chmod +x "${INSTALL_DIR}/ship.py"
}

# Install systemd units
install_systemd_units() {
    log_info "Installing systemd units..."
    
    local SYSTEMD_FILES=("ship.service" "ship.timer")
    
    for FILE in "${SYSTEMD_FILES[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${FILE}" ]]; then
            cp "${SCRIPT_DIR}/${FILE}" "/etc/systemd/system/"
            log_success "Installed ${FILE}"
        else
            log_warning "${FILE} not found, skipping"
        fi
    done
    
    # Reload systemd
    systemctl daemon-reload
    log_success "Systemd units reloaded"
}

# Configure systemd service
configure_systemd() {
    log_info "Configuring systemd service..."
    
    # Enable timer
    if systemctl enable ship.timer; then
        log_success "Enabled ship.timer"
    else
        log_warning "Failed to enable timer"
    fi
    
    # Start timer
    if systemctl start ship.timer; then
        log_success "Started ship.timer"
    else
        log_warning "Failed to start timer"
    fi
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    # Test configuration loading
    if sudo -u "${UPDATER_USER}" "${INSTALL_DIR}/venv/bin/python" "${INSTALL_DIR}/ship.py" --check-only 2>/dev/null; then
        log_success "Configuration test passed"
    else
        log_warning "Configuration test failed - check configuration file"
    fi
    
    # Check systemd status
    if systemctl is-active --quiet ship.timer; then
        log_success "Timer is active"
    else
        log_warning "Timer is not active"
    fi
    
    # Show next scheduled run
    local NEXT_RUN
    NEXT_RUN=$(systemctl list-timers ship.timer --no-pager --no-legend | awk '{print $1, $2}' | head -1)
    if [[ -n "${NEXT_RUN}" ]]; then
        log_info "Next scheduled run: ${NEXT_RUN}"
    fi
}

# Display post-installation information
show_post_install_info() {
    log_success "Installation completed successfully!"
    
    echo
    echo "=== POST-INSTALLATION STEPS ==="
    echo
    echo "1. Edit configuration file:"
    echo "   sudo nano ${CONFIG_DIR}/ship.toml"
    echo
    echo "2. Test configuration:"
    echo "   sudo -u ${UPDATER_USER} ${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/ship.py --check-only"
    echo
    echo "3. Manual test run:"
    echo "   sudo systemctl start ship.service"
    echo
    echo "4. Monitor logs:"
    echo "   sudo journalctl -u ship.service -f"
    echo "   sudo tail -f /var/log/ship.log"
    echo
    echo "5. Check timer status:"
    echo "   systemctl status ship.timer"
    echo
    echo "=== IMPORTANT SECURITY NOTES ==="
    echo "- Review and customize the configuration file"
    echo "- Set up appropriate SSH keys for Git/SFTP access"
    echo "- Test all update sources before production use"
    echo "- Monitor logs regularly for any issues"
    echo
}

# Main installation function
main() {
    log_info "Starting Ship Application Updater installation..."
    
    check_root
    check_requirements
    setup_user_and_directories
    setup_python_environment
    install_application
    install_systemd_units
    configure_systemd
    test_installation
    show_post_install_info
}

# Run main function with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
