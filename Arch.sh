#!/bin/bash

# Define disk (change as needed)
DISK="/dev/nvme0n1"
CRYPTROOT="cryptroot"
BTRFS_VOL="arch_root"

# Ensure the disk exists
lsblk $DISK || { echo "Disk not found!"; exit 1; }

# Partitioning (GPT, 512M EFI, rest for Linux root)
parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 512MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary 512MiB 100%

# Encrypt root partition
cryptsetup luksFormat ${DISK}2
cryptsetup open ${DISK}2 $CRYPTROOT

# Create Btrfs filesystem
mkfs.btrfs /dev/mapper/$CRYPTROOT
mount /dev/mapper/$CRYPTROOT /mnt

# Create subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Mount subvolumes
mount -o noatime,compress=zstd,subvol=@ /dev/mapper/$CRYPTROOT /mnt
mkdir -p /mnt/{boot,home,var,.snapshots}
mount -o noatime,compress=zstd,subvol=@home /dev/mapper/$CRYPTROOT /mnt/home
mount -o noatime,compress=zstd,subvol=@var /dev/mapper/$CRYPTROOT /mnt/var
mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/$CRYPTROOT /mnt/.snapshots

# Format and mount EFI partition
mkfs.fat -F32 ${DISK}1
mkdir -p /mnt/boot
mount ${DISK}1 /mnt/boot

# Install base system
pacstrap /mnt base linux linux-firmware btrfs-progs grub efibootmgr

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into system
arch-chroot /mnt /bin/bash <<EOF

# Set up locale, time, hostname
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "archlinux" > /etc/hostname
locale-gen

# Set root password
echo "Set root password"
passwd

# Configure mkinitcpio
sed -i 's/HOOKS=(.*)/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck btrfs)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
echo 'GRUB_CMDLINE_LINUX="cryptdevice=UUID=$(blkid -s UUID -o value ${DISK}2):$CRYPTROOT root=/dev/mapper/$CRYPTROOT"' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Unmount and reboot
umount -R /mnt
echo "Installation complete! Reboot now."
