#!/bin/bash

# ebpH Setup Script for Ubuntu 22.04 LTS
# This script will install all required dependencies and fix common issues

set -e  # Exit on any error

echo "=== ebpH Setup Script for Ubuntu 22.04 LTS ==="
echo "This will install all dependencies and fix common issues."
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "Please run this script as a regular user (not root). It will use sudo when needed."
   exit 1
fi

# Check Ubuntu version
if ! lsb_release -d | grep -q "Ubuntu 22.04"; then
    echo "WARNING: This script is optimized for Ubuntu 22.04 LTS. Other versions may work but are not guaranteed."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "=== Step 1: Checking kernel requirements ==="
KERNEL_VERSION=$(uname -r)
echo "Current kernel: $KERNEL_VERSION"

# Check for required kernel configs
REQUIRED_CONFIGS=(
    "CONFIG_BPF"
    "CONFIG_BPF_SYSCALL"
    "CONFIG_BPF_JIT"
    "CONFIG_TRACEPOINTS"
    "CONFIG_BPF_LSM"
    "CONFIG_DEBUG_INFO_BTF"
)

CONFIG_FILE="/boot/config-$(uname -r)"
if [[ -f $CONFIG_FILE ]]; then
    echo "Checking kernel configuration..."
    MISSING_CONFIGS=()
    for config in "${REQUIRED_CONFIGS[@]}"; do
        if ! grep -q "${config}=y" "$CONFIG_FILE" 2>/dev/null; then
            MISSING_CONFIGS+=("$config")
        fi
    done

    if [[ ${#MISSING_CONFIGS[@]} -gt 0 ]]; then
        echo "ERROR: Missing required kernel configurations:"
        printf ' - %s\n' "${MISSING_CONFIGS[@]}"
        echo ""
        echo "You need a kernel compiled with eBPF LSM support."
        echo "For Ubuntu 22.04, try: sudo apt install linux-generic-hwe-22.04"
        echo "Then reboot and run this script again."
        exit 1
    fi
    echo "✓ All required kernel configurations found"
else
    echo "WARNING: Cannot check kernel config file. Proceeding anyway..."
fi

echo ""
echo "=== Step 2: Installing system dependencies ==="

# Update package lists
sudo apt update

# Install essential build tools and Python
sudo apt install -y \
    build-essential \
    cmake \
    git \
    python3-dev \
    python3-pip \
    python3-venv \
    pkg-config \
    libelf-dev \
    zlib1g-dev \
    llvm \
    clang \
    libbpf-dev

# Install BCC dependencies
sudo apt install -y \
    bpfcc-tools \
    python3-bpfcc \
    libbpf-dev \
    linux-headers-$(uname -r)

echo "✓ System dependencies installed"

echo ""
echo "=== Step 3: Setting up Python virtual environment ==="

# Create virtual environment if it doesn't exist
if [[ ! -d "ebph-venv" ]]; then
    python3 -m venv ebph-venv
    echo "✓ Virtual environment created"
else
    echo "✓ Virtual environment already exists"
fi

# Activate virtual environment
source ebph-venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

echo "✓ Virtual environment activated"

echo ""
echo "=== Step 4: Installing Python dependencies ==="

# Install required Python packages in correct order
pip install --no-cache-dir \
    python-daemon==2.2.4 \
    fastapi \
    uvicorn \
    requests \
    ratelimit \
    requests-unixsocket \
    proc \
    colorama

# Install the package in development mode
pip install -e .

echo "✓ Python dependencies installed"

echo ""
echo "=== Step 5: Checking and fixing common issues ==="

# Check if eBPF programs can be loaded (requires root)
echo "Testing eBPF program loading (requires root)..."
sudo -E env PATH=$PATH python3 -c "
import sys
sys.path.insert(0, '.')
try:
    from bcc import BPF
    # Simple test program
    prog = '''
    int hello(void *ctx) {
        return 0;
    }
    '''
    b = BPF(text=prog)
    print('✓ eBPF program loading test successful')
    del b
except Exception as e:
    print(f'✗ eBPF test failed: {e}')
    sys.exit(1)
"

# Fix library path issues
echo "Setting up library paths..."
sudo ldconfig

# Ensure proper permissions for BPF
if [[ -d /sys/fs/bpf ]]; then
    sudo chmod 755 /sys/fs/bpf
    echo "✓ BPF filesystem permissions set"
fi

echo ""
echo "=== Step 6: Building and installing ebpH ==="

# Clean any previous builds
sudo rm -rf build/ dist/ *.egg-info/ || true

# Build with verbose output
python setup.py build_ext --inplace --force

# Install in development mode
pip install -e . --force-reinstall

echo "✓ ebpH built and installed"

echo ""
echo "=== Step 7: Setting up systemd service ==="

# Install systemd service
sudo bash systemd/create_service.sh

echo "✓ Systemd service installed"

echo ""
echo "=== Step 8: Final verification ==="

# Test imports
python3 -c "
import ebph
import ebph.bpf_program
import ebph.structs
import ebph.daemon_mixin
print('✓ All ebpH modules import successfully')
"

# Test daemon startup (without actually running)
echo "Testing daemon initialization..."
sudo -E env PATH=$PATH python3 -c "
import sys
sys.path.insert(0, '.')
from ebph.ebphd import main
print('✓ Daemon can be initialized')
"

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "To start ebpH:"
echo "1. Start daemon: sudo systemctl start ebphd"
echo "2. Check status: sudo systemctl status ebphd"
echo "3. Check daemon status: sudo ebph admin status"
echo "4. List processes: sudo ebph ps"
echo ""
echo "To activate the Python environment in future sessions:"
echo "source ebph-venv/bin/activate"
echo ""
echo "If you encounter issues:"
echo "1. Check logs: sudo journalctl -u ebphd -f"
echo "2. Check kernel logs: sudo dmesg | tail"
echo "3. Verify eBPF support: ls /sys/fs/bpf"
