#!/bin/bash

# Script to setup Btrfs subvolumes on a new partition.
# Requires root privileges.

set -e # Exit on error

# Configuration
DEVICE="/dev/sdX" # Replace with your target device (e.g., /dev/sda)
MOUNT_POINT="/mnt/btrfs"
ROOT_SUBVOLUME="root"
HOME_SUBVOLUME="home"
VAR_SUBVOLUME="var"
LOG_SUBVOLUME="log"
CACHE_SUBVOLUME="cache"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script requires root privileges. Please run as root."
  exit 1
fi

# Check if the device exists
if [[ ! -b "$DEVICE" ]]; then
  echo "Device $DEVICE not found."
  exit 1
fi

# Partition the disk (Example: using parted. Adjust as needed)
echo "Partitioning the disk..."
parted -s "$DEVICE" mklabel gpt
parted -s "$DEVICE" mkpart primary btrfs 0% 100%
PARTITION="${DEVICE}1" # Assumes the first partition is the Btrfs partition.

# Create the Btrfs filesystem
echo "Creating Btrfs filesystem..."
mkfs.btrfs -L "btrfs-root" "$PARTITION"

# Mount the Btrfs filesystem
echo "Mounting the Btrfs filesystem..."
mkdir -p "$MOUNT_POINT"
mount "$PARTITION" "$MOUNT_POINT"

# Create subvolumes
echo "Creating subvolumes..."
btrfs subvolume create "$MOUNT_POINT/$ROOT_SUBVOLUME"
btrfs subvolume create "$MOUNT_POINT/$HOME_SUBVOLUME"
btrfs subvolume create "$MOUNT_POINT/$VAR_SUBVOLUME"
btrfs subvolume create "$MOUNT_POINT/$LOG_SUBVOLUME"
btrfs subvolume create "$MOUNT_POINT/$CACHE_SUBVOLUME"

# Unmount the filesystem
umount "$MOUNT_POINT"

# Generate fstab entries (Example. Adapt to your needs)
echo "Generating fstab entries..."
echo "UUID=$(blkid -o value -s UUID "$PARTITION") / btrfs subvol=$ROOT_SUBVOLUME,defaults,noatime,compress=zstd 0 1" >> /etc/fstab
echo "UUID=$(blkid -o value -s UUID "$PARTITION") /home btrfs subvol=$HOME_SUBVOLUME,defaults,noatime,compress=zstd 0 2" >> /etc/fstab
echo "UUID=$(blkid -o value -s UUID "$PARTITION") /var btrfs subvol=$VAR_SUBVOLUME,defaults,noatime,compress=zstd 0 2" >> /etc/fstab
echo "UUID=$(blkid -o value -s UUID "$PARTITION") /var/log btrfs subvol=$LOG_SUBVOLUME,defaults,noatime,compress=zstd 0 2" >> /etc/fstab
echo "UUID=$(blkid -o value -s UUID "$PARTITION") /var/cache btrfs subvol=$CACHE_SUBVOLUME,defaults,noatime,compress=zstd 0 2" >> /etc/fstab

echo "Btrfs subvolume setup complete."

# Important next steps:
# 1. Boot from a live environment, and copy your system to the root subvolume.
# 2. Configure your bootloader (GRUB) to boot from the root subvolume.
# 3. Reboot into your new Btrfs system.
