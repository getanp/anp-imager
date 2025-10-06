#!/bin/bash
set -eu

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_FILES="$(cd "$SCRIPT_DIR/../../boot_files" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Color codes for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Check required commands
for cmd in parted mkfs.vfat lsblk wipefs grub-install; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}Error: Required command '$cmd' not found${NC}"
        exit 1
    fi
done

# Check if boot files directory exists
if [ ! -d "$BOOT_FILES" ]; then
    echo -e "${RED}Error: Boot files directory not found: $BOOT_FILES${NC}"
    exit 1
fi

for file in vmlinuz initrd.img; do
    if [ ! -f "$BOOT_FILES/$file" ]; then
        echo -e "${RED}Error: Required file not found: $BOOT_FILES/$file${NC}"
        exit 1
    fi
done

echo -e "${GREEN}=== Disk Imager USB Creator ===${NC}"
echo ""
echo "Boot files location: $BOOT_FILES"
echo ""

# List USB devices
echo "Detecting USB devices..."
echo ""

# Build list of USB devices
USB_DEVICES=()
while IFS= read -r line; do
    DEV=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    MODEL=$(echo "$line" | cut -d' ' -f3-)
    USB_DEVICES+=("$DEV|$SIZE|$MODEL")
done < <(lsblk -d -n -o NAME,SIZE,TRAN,MODEL | grep usb)

if [ ${#USB_DEVICES[@]} -eq 0 ]; then
    echo -e "${RED}No USB devices found!${NC}"
    echo ""
    echo "All block devices:"
    lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL
    exit 1
fi

# Display USB devices with numbers
echo "Available USB devices:"
echo ""
i=1
for dev_info in "${USB_DEVICES[@]}"; do
    DEV=$(echo "$dev_info" | cut -d'|' -f1)
    SIZE=$(echo "$dev_info" | cut -d'|' -f2)
    MODEL=$(echo "$dev_info" | cut -d'|' -f3-)
    printf "%d) /dev/%s  %s  %s\n" "$i" "$DEV" "$SIZE" "$MODEL"
    i=$((i+1))
done
echo ""

# Get user selection
while true; do
    read -p "Select USB device (1-${#USB_DEVICES[@]}) or 'q' to quit: " selection
    
    if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#USB_DEVICES[@]} ]; then
        break
    fi
    
    echo -e "${RED}Invalid selection. Please try again.${NC}"
done

# Get selected device
SELECTED_INFO="${USB_DEVICES[$((selection-1))]}"
USB_DEVICE="/dev/$(echo "$SELECTED_INFO" | cut -d'|' -f1)"
USB_SIZE=$(echo "$SELECTED_INFO" | cut -d'|' -f2)
USB_MODEL=$(echo "$SELECTED_INFO" | cut -d'|' -f3-)

echo ""
echo -e "${YELLOW}WARNING: This will ERASE ALL DATA on the selected device!${NC}"
echo ""
echo "Selected device: $USB_DEVICE"
echo "Size: $USB_SIZE"
echo "Model: $USB_MODEL"
echo ""
lsblk "$USB_DEVICE" 2>/dev/null || true
echo ""

# Confirm
read -p "Type 'YES' (in capitals) to continue: " confirm
if [ "$confirm" != "YES" ]; then
    echo "Cancelled."
    exit 0
fi

# Optional NFS configuration
echo ""
read -p "Configure NFS share? (y/n): " nfs_config
NFS_SHARE=""
if [ "$nfs_config" = "y" ] || [ "$nfs_config" = "Y" ]; then
    read -p "Enter NFS share (e.g., 192.168.1.100:/mnt/img): " NFS_SHARE
fi

echo ""
echo -e "${GREEN}[*] Starting USB creation...${NC}"

# Unmount any mounted partitions
echo "[*] Unmounting any existing partitions..."
for part in "${USB_DEVICE}"*[0-9] "${USB_DEVICE}p"*[0-9]; do
    if [ -b "$part" ]; then
        umount "$part" 2>/dev/null || true
        swapoff "$part" 2>/dev/null || true
    fi
done

# Give system time to release the device
sleep 1

# Wipe any existing filesystem signatures
echo "[*] Wiping existing filesystem signatures..."
wipefs -a "$USB_DEVICE" || true
dd if=/dev/zero of="$USB_DEVICE" bs=1M count=10 conv=fsync 2>/dev/null || true

# Give kernel time to notice changes
sleep 2
blockdev --rereadpt "$USB_DEVICE" 2>/dev/null || true
sleep 1

# Partitioning with parted
echo "[*] Creating GPT partition table..."
parted -s "$USB_DEVICE" mklabel gpt || {
    echo -e "${RED}Error: Failed to create partition table${NC}"
    exit 1
}

echo "[*] Creating EFI system partition..."
parted -s "$USB_DEVICE" mkpart primary fat32 1MiB 100% || {
    echo -e "${RED}Error: Failed to create partition${NC}"
    exit 1
}

parted -s "$USB_DEVICE" set 1 boot on || true
parted -s "$USB_DEVICE" set 1 esp on || true

# Force kernel to re-read partition table
echo "[*] Refreshing partition table..."
partprobe "$USB_DEVICE" 2>/dev/null || blockdev --rereadpt "$USB_DEVICE" 2>/dev/null || true
sleep 3

# Find the partition
PARTITION=""
for attempt in 1 2 3 4 5; do
    if [ -b "${USB_DEVICE}1" ]; then
        PARTITION="${USB_DEVICE}1"
        break
    elif [ -b "${USB_DEVICE}p1" ]; then
        PARTITION="${USB_DEVICE}p1"
        break
    fi
    echo "[*] Waiting for partition to appear (attempt $attempt/5)..."
    sleep 2
    partprobe "$USB_DEVICE" 2>/dev/null || true
done

if [ -z "$PARTITION" ] || [ ! -b "$PARTITION" ]; then
    echo -e "${RED}Error: Partition not found after creation${NC}"
    echo "Expected: ${USB_DEVICE}1 or ${USB_DEVICE}p1"
    exit 1
fi

echo "[*] Using partition: $PARTITION"

# Format
echo "[*] Formatting partition as FAT32..."
mkfs.vfat -F32 -n "IMAGER" "$PARTITION" || {
    echo -e "${RED}Error: Failed to format partition${NC}"
    exit 1
}

# Wait for filesystem to be ready
sync
sleep 2

# Mount
echo "[*] Mounting USB..."
MOUNT_POINT=$(mktemp -d)
trap "umount '$MOUNT_POINT' 2>/dev/null || true; rmdir '$MOUNT_POINT' 2>/dev/null || true" EXIT

mount "$PARTITION" "$MOUNT_POINT" || {
    echo -e "${RED}Error: Failed to mount partition${NC}"
    exit 1
}

# Create directory structure
echo "[*] Creating directory structure..."
mkdir -p "$MOUNT_POINT/boot"

# Install GRUB bootloader
echo "[*] Installing GRUB bootloader..."
grub-install --target=x86_64-efi \
             --efi-directory="$MOUNT_POINT" \
             --boot-directory="$MOUNT_POINT/boot" \
             --removable \
             --no-nvram || {
    echo -e "${RED}Error: Failed to install GRUB${NC}"
    exit 1
}

# Copy kernel and initrd
echo "[*] Copying kernel and initrd..."
cp "$BOOT_FILES/vmlinuz" "$MOUNT_POINT/boot/"
cp "$BOOT_FILES/initrd.img" "$MOUNT_POINT/boot/"

# Create GRUB config
echo "[*] Creating GRUB configuration..."
cat > "$MOUNT_POINT/boot/grub/grub.cfg" << EOF
set timeout=5
set default=0

menuentry "Disk Imager" {
    linux /boot/vmlinuz quiet splash${NFS_SHARE:+ img_nfs=$NFS_SHARE}
    initrd /boot/initrd.img
}

menuentry "Disk Imager (Manual Network)" {
    linux /boot/vmlinuz quiet splash
    initrd /boot/initrd.img
}

menuentry "Disk Imager (Debug Mode)" {
    linux /boot/vmlinuz console=tty0 debug
    initrd /boot/initrd.img
}

menuentry "System Shell" {
    linux /boot/vmlinuz init=/bin/sh
    initrd /boot/initrd.img
}
EOF

# Sync and unmount
echo "[*] Syncing and unmounting..."
sync
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"
trap - EXIT

echo ""
echo -e "${GREEN}✓ Bootable USB created successfully!${NC}"
echo ""
echo "Device: $USB_DEVICE ($USB_SIZE)"
echo "Partition: $PARTITION"
[ -n "$NFS_SHARE" ] && echo "NFS Share: $NFS_SHARE"
echo ""
echo "You can now boot from this USB drive."
echo ""
