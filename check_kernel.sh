#!/bin/bash

# Quick kernel compatibility check for ebpH

echo "=== ebpH Kernel Compatibility Check ==="
echo ""

# Check kernel version
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d. -f2)

echo "Current kernel: $KERNEL_VERSION"

# Check if kernel is 5.8+
if [[ $KERNEL_MAJOR -lt 5 ]] || [[ $KERNEL_MAJOR -eq 5 && $KERNEL_MINOR -lt 8 ]]; then
    echo "❌ FAIL: ebpH requires Linux 5.8+. Current version: $KERNEL_VERSION"
    echo ""
    echo "Solutions:"
    echo "1. For Ubuntu 22.04: sudo apt install linux-generic-hwe-22.04"
    echo "2. For Ubuntu 20.04: sudo apt install linux-generic-hwe-20.04"
    echo "3. Update to a newer distribution"
    exit 1
else
    echo "✅ PASS: Kernel version meets minimum requirement (5.8+)"
fi

# Check for required configs
echo ""
echo "Checking kernel configuration..."

CONFIG_FILE="/boot/config-$(uname -r)"
PROC_CONFIG="/proc/config.gz"

# Try to find config file
if [[ -f $CONFIG_FILE ]]; then
    CONFIG_SOURCE=$CONFIG_FILE
    CONFIG_CMD="cat $CONFIG_FILE"
elif [[ -f $PROC_CONFIG ]]; then
    CONFIG_SOURCE=$PROC_CONFIG
    CONFIG_CMD="zcat $PROC_CONFIG"
else
    echo "⚠️  WARNING: Cannot find kernel config file"
    echo "Looked for:"
    echo "  - $CONFIG_FILE"
    echo "  - $PROC_CONFIG"
    echo ""
    echo "Proceeding without config check..."
    CONFIG_SOURCE=""
fi

if [[ -n $CONFIG_SOURCE ]]; then
    echo "Using config from: $CONFIG_SOURCE"

    REQUIRED_CONFIGS=(
        "CONFIG_BPF=y"
        "CONFIG_BPF_SYSCALL=y"
        "CONFIG_BPF_JIT=y"
        "CONFIG_TRACEPOINTS=y"
        "CONFIG_BPF_LSM=y"
        "CONFIG_DEBUG_INFO_BTF=y"
    )

    MISSING_CONFIGS=()

    for config in "${REQUIRED_CONFIGS[@]}"; do
        if ! $CONFIG_CMD | grep -q "^$config" 2>/dev/null; then
            MISSING_CONFIGS+=("$config")
        else
            echo "✅ Found: $config"
        fi
    done

    # Special check for LSM ordering
    LSM_ORDER=$($CONFIG_CMD | grep "^CONFIG_LSM=" | cut -d'"' -f2)
    if [[ -n $LSM_ORDER ]]; then
        if echo "$LSM_ORDER" | grep -q "bpf"; then
            echo "✅ Found: BPF LSM in order: $LSM_ORDER"
        else
            echo "⚠️  WARNING: BPF not found in LSM order: $LSM_ORDER"
            echo "   You may need to add 'lsm=...,bpf' to kernel command line"
        fi
    fi

    if [[ ${#MISSING_CONFIGS[@]} -gt 0 ]]; then
        echo ""
        echo "❌ FAIL: Missing required kernel configurations:"
        for config in "${MISSING_CONFIGS[@]}"; do
            echo "  ❌ $config"
        done
        echo ""
        echo "Your kernel was not compiled with eBPF LSM support."
        echo ""
        echo "Solutions:"
        echo "1. For Ubuntu 22.04: sudo apt install linux-generic-hwe-22.04"
        echo "2. For Ubuntu 20.04: sudo apt install linux-generic-hwe-20.04"
        echo "3. Use a distribution with eBPF LSM enabled (like recent Ubuntu/Fedora)"
        echo "4. Compile your own kernel with the required options"
        exit 1
    else
        echo ""
        echo "✅ PASS: All required kernel configurations found!"
    fi
fi

# Check BPF filesystem
echo ""
echo "Checking BPF filesystem..."
if [[ -d /sys/fs/bpf ]]; then
    echo "✅ PASS: BPF filesystem mounted at /sys/fs/bpf"
else
    echo "⚠️  WARNING: BPF filesystem not found"
    echo "   Try: sudo mount -t bpf bpf /sys/fs/bpf"
fi

# Check if BCC is available
echo ""
echo "Checking BCC availability..."
if python3 -c "import bcc" 2>/dev/null; then
    echo "✅ PASS: BCC Python bindings available"
else
    echo "❌ FAIL: BCC Python bindings not available"
    echo "   Install with: sudo apt install python3-bpfcc"
fi

# Test basic BPF program loading (if running as root)
if [[ $EUID -eq 0 ]]; then
    echo ""
    echo "Testing BPF program loading..."
    if python3 -c "
from bcc import BPF
try:
    b = BPF(text='int test(void *ctx) { return 0; }')
    print('✅ PASS: BPF program loading works')
    del b
except Exception as e:
    print('❌ FAIL: BPF program loading failed:', e)
    exit(1)
" 2>/dev/null; then
        :  # Success message already printed
    else
        echo "❌ FAIL: BPF program loading test failed"
        exit 1
    fi
else
    echo ""
    echo "⚠️  NOTE: Run as root to test BPF program loading"
fi

echo ""
echo "=== Kernel Compatibility Check Complete ==="
echo ""
echo "If all checks passed, your system should be compatible with ebpH!"
echo "Run the setup script: bash fix_ebph_setup.sh"
