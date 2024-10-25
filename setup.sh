#!/bin/bash
# setup.sh

set -e  # Exit on error

# Get absolute path of script directory
REPO_DIR="$(dirname "$(readlink -f "$0")")"
INSTALL_PREFIX="${1:-/usr/lib/slurm-job-exporter}"
SYSTEMD_DIR="/etc/systemd/system"
VENV_DIR="${INSTALL_PREFIX}/venv"
SERVICE_USER="slurm-job-exporter"
LOG_DIR="/var/log/slurm-job-exporter"
RUN_DIR="/var/run/slurm-job-exporter"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Create service user if doesn't exist
if ! id "${SERVICE_USER}" &>/dev/null; then
    useradd -r -s /sbin/nologin "${SERVICE_USER}"
fi

# Create directories
mkdir -p "${INSTALL_PREFIX}"
mkdir -p "${SYSTEMD_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p "${RUN_DIR}"

# Copy files to installation directory
cp -r "${REPO_DIR}/requirements.txt" "${INSTALL_PREFIX}/"
cp -r "${REPO_DIR}/slurm-job-exporter.py" "${INSTALL_PREFIX}/"
cp -r "${REPO_DIR}/run.sh" "${INSTALL_PREFIX}/"
cp -r "${REPO_DIR}/slurm-job-exporter.service" "${SYSTEMD_DIR}/"

# Set permissions
chmod 755 "${INSTALL_PREFIX}/run.sh"
chmod 644 "${SYSTEMD_DIR}/slurm-job-exporter.service"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_PREFIX}"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${LOG_DIR}"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${RUN_DIR}"

# Create and setup Python virtual environment
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install -r "${INSTALL_PREFIX}/requirements.txt"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${VENV_DIR}"

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable slurm-job-exporter.service
systemctl start slurm-job-exporter.service

echo "Installation and setup completed successfully"