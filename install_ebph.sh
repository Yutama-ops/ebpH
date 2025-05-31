#!/bin/bash

# ebpH Installation Script
# This will install ebpH to /opt/ebpH with proper systemd integration

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo "=== Installing ebpH to /opt/ebpH ==="

# Create installation directory
mkdir -p /opt/ebpH

# Copy all files
echo "Copying files..."
cp -r . /opt/ebpH/
cd /opt/ebpH

# Set proper ownership
chown -R root:root /opt/ebpH
chmod +x /opt/ebpH/bin/*

# Create and activate virtual environment
echo "Setting up Python virtual environment..."
python3 -m venv ebph-venv
source ebph-venv/bin/activate

# Install dependencies
pip install --upgrade pip setuptools wheel
pip install --no-cache-dir \
    python-daemon==2.2.4 \
    fastapi \
    uvicorn \
    requests \
    ratelimit \
    requests-unixsocket \
    proc \
    colorama

# Install ebpH
pip install -e .

# Install improved systemd service
echo "Installing systemd service..."
cp systemd/ebphd_fixed.service /etc/systemd/system/ebphd.service
systemctl daemon-reload
systemctl enable ebphd

# Create symlinks for convenience
echo "Creating command symlinks..."
ln -sf /opt/ebpH/ebph-venv/bin/ebph /usr/local/bin/ebph
ln -sf /opt/ebpH/ebph-venv/bin/ebphd /usr/local/bin/ebphd

# Set up BPF filesystem if needed
if [[ ! -d /sys/fs/bpf ]]; then
    mkdir -p /sys/fs/bpf
    mount -t bpf bpf /sys/fs/bpf
    echo "bpf /sys/fs/bpf bpf defaults 0 0" >> /etc/fstab
fi

# Fix permissions
chmod 755 /sys/fs/bpf

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "Commands available:"
echo "  sudo systemctl start ebphd    # Start daemon"
echo "  sudo systemctl status ebphd   # Check status"
echo "  sudo ebph admin status        # Check daemon status"
echo "  sudo ebph ps                  # List monitored processes"
echo ""
echo "Logs:"
echo "  sudo journalctl -u ebphd -f   # Follow daemon logs"
echo ""
echo "ebpH is installed in /opt/ebpH"
