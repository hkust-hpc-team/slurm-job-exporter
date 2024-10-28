#!/usr/bin/env bash

set -euo pipefail
umask 027

# Configuration
REPO_DIR="$(dirname "$(readlink -f "$0")")"
ACTION="${1:-install}"
INSTALL_PREFIX="${2:-/usr/lib/slurm-job-exporter}"
SYSTEMD_DIR="/etc/systemd/system"
VENV_DIR="${INSTALL_PREFIX}/venv"
SERVICE_USER="slurm-job-exporter"
SERVICE_NAME="slurm-job-exporter"
LOG_DIR="/var/log/slurm-job-exporter"
RUN_DIR="/var/run/slurm-job-exporter"
LOG_FILE="/var/log/${SERVICE_NAME}_setup.log"

# Ensure log directory exists
mkdir -p "$(dirname "${LOG_FILE}")"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" | tee -a "${LOG_FILE}" >&2
}

error() {
    log "ERROR: $*"
}

help() {
    echo "Usage: $0 {install|uninstall} [install_prefix]"
    echo "       install        Install the slurm-job-exporter service"
    echo "       uninstall      Uninstall the slurm-job-exporter service"
    echo "       install_prefix Optional installation directory prefix"
    echo "Default install_prefix: /usr/lib/slurm-job-exporter"
}

# Check root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Installation function
install() {
    log "Starting installation..."

    # Check for required commands
    command -v python3 >/dev/null 2>&1 || { error "python3 is not installed."; exit 1; }
    command -v pip3 >/dev/null 2>&1 || { error "pip3 is not installed."; exit 1; }

    # Create service user if doesn't exist
    if ! id "${SERVICE_USER}" &>/dev/null; then
        useradd -r -s /sbin/nologin -d /nonexistent -c "Slurm Job Exporter Service User" "${SERVICE_USER}"
        log "Created service user ${SERVICE_USER}"
    fi

    # Create directories
    mkdir -p "${INSTALL_PREFIX}" "${LOG_DIR}" "${RUN_DIR}"

    # Copy files
    /usr/bin/install -m 755 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${REPO_DIR}/requirements.txt" "${INSTALL_PREFIX}/"
    /usr/bin/install -m 755 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${REPO_DIR}/slurm-job-exporter.py" "${INSTALL_PREFIX}/"
    /usr/bin/install -m 755 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${REPO_DIR}/run.sh" "${INSTALL_PREFIX}/"
    /usr/bin/install -m 644 -o root -g root "${REPO_DIR}/slurm-job-exporter.service" "${SYSTEMD_DIR}/"

    # Set ownership on directories
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_PREFIX}" "${LOG_DIR}" "${RUN_DIR}"

    # Setup Python virtual environment
    log "Setting up Python virtual environment..."
    if ! python3 -m venv "${VENV_DIR}"; then
        error "Failed to create virtual environment"
        exit 1
    fi

    if ! "${VENV_DIR}/bin/pip" install -r "${INSTALL_PREFIX}/requirements.txt"; then
        error "Failed to install Python dependencies"
        exit 1
    fi
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${VENV_DIR}"
    chmod -R 750 "${VENV_DIR}"

    # Enable and start service
    log "Enabling and starting service..."
    systemctl daemon-reload
    if ! systemctl enable "${SERVICE_NAME}.service"; then
        error "Failed to enable service"
        exit 1
    fi
    if ! systemctl start "${SERVICE_NAME}.service"; then
        error "Failed to start service"
        exit 1
    fi

    # Verify service status
    sleep 2
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        error "Service ${SERVICE_NAME} failed to start"
        systemctl status "${SERVICE_NAME}" --no-pager
        journalctl -u "${SERVICE_NAME}" --no-pager | tail -n 20
        exit 1
    fi

    log "Installation completed successfully"
}

# Uninstallation function
uninstall() {
    log "Starting uninstallation..."

    # Stop and disable service
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        systemctl stop "${SERVICE_NAME}.service"
        systemctl disable "${SERVICE_NAME}.service"
        log "Service stopped and disabled"
    fi

    # Remove service file
    if [ -f "${SYSTEMD_DIR}/${SERVICE_NAME}.service" ]; then
        rm -f "${SYSTEMD_DIR}/${SERVICE_NAME}.service"
        log "Removed service file"
    fi

    # Remove installed files and directories
    [ -d "${INSTALL_PREFIX}" ] && rm -rf "${INSTALL_PREFIX}"
    [ -d "${LOG_DIR}" ] && rm -rf "${LOG_DIR}"
    [ -d "${RUN_DIR}" ] && rm -rf "${RUN_DIR}"
    log "Removed installation directories"

    # Remove service user if no processes are running
    if id "${SERVICE_USER}" &>/dev/null; then
        if pgrep -u "${SERVICE_USER}" >/dev/null; then
            error "Processes are still running under user ${SERVICE_USER}. Cannot remove user."
            exit 1
        else
            userdel -r "${SERVICE_USER}"
            log "Removed service user ${SERVICE_USER}"
        fi
    fi

    systemctl daemon-reload
    log "Uninstallation completed successfully"
}

check_root

case "${ACTION}" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    *)
        help
        exit 1
        ;;
esac