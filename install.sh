#!/bin/bash

timedatectl set-timezone America/New_York
reflector -c US --verbose -l 15 -n 5 -p http --sort rate --save /etc/pacman.d/mirrorlist

set -e  # Exit on error

# VARIABLES
DISK="/dev/sdX"   # Replace with your disk
HOSTNAME="archlinux"
USERNAME="user"
PASSWORD="password"  # Change this later!

echo "⚡ Arch Linux Installation - Btrfs + Encryption + ZRAM + Timeshift + Qtile ⚡"

# 1️⃣ Partitioning (UEFI)
echo "[+] Partitioning disk..."
wipefs --all --force $DISK
parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 512MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary ext4 512MiB 100%

# 2️⃣ Encryption (LUKS)
echo "[+] Setting up LUKS encryption..."
cryptsetup luksFormat "${DISK}p2"
cryptsetup open "${DISK}p2" cryptroot

# 3️⃣ Formatting Partitions
echo "[+] Formatting partitions..."
mkfs.fat -F32 "${DISK}p1"
mkfs.btrfs -f /dev/mapper/cryptroot

# 4️⃣ Btrfs Subvolumes
echo "[+] Creating Btrfs subvolumes..."
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

# 5️⃣ Mounting Btrfs Subvolumes
echo "[+] Mounting Btrfs subvolumes..."
mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,var,.snapshots}
mount -o noatime,compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount "${DISK}p1" /mnt/boot

# 6️⃣ Install Base System
echo "[+] Installing base system..."
pacstrap /mnt base linux linux-firmware btrfs-progs vim nano

# 7️⃣ Generate fstab
echo "[+] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# 8️⃣ Configure System
echo "[+] Configuring system..."
arch-chroot /mnt /bin/bash <<EOF
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$(curl -s https://ipapi.co/timezone) /etc/localtime
hwclock --systohc
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "127.0.1.1   $HOSTNAME" >> /etc/hosts

# 9️⃣ Install Bootloader (GRUB)
echo "[+] Installing bootloader..."
pacman -Sy --noconfirm grub efibootmgr dosfstools mtools
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
echo 'GRUB_CMDLINE_LINUX="cryptdevice=/dev/sdXp2:cryptroot root=/dev/mapper/cryptroot"' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# 🔟 Set up Users
echo "[+] Creating user..."
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# 🛠 Enable Services
echo "[+] Enabling services..."
systemctl enable NetworkManager

# 🏠 ZRAM Setup
echo "[+] Configuring ZRAM..."
echo "zram" > /etc/modules-load.d/zram.conf
echo "options zram num_devices=1" > /etc/modprobe.d/zram.conf
echo "KERNEL==\"zram0\", ATTR{disksize}=\"2G\", RUN=\"/sbin/mkswap /dev/zram0\", TAG+=\"systemd\"" > /etc/udev/rules.d/99-zram.rules
echo "/dev/zram0 none swap sw 0 0" >> /etc/fstab

# 🛡 Install Timeshift
echo "[+] Installing Timeshift..."
pacman -Sy --noconfirm timeshift

# 🎨 Install Qtile
echo "[+] Installing Qtile..."
pacman -Sy --noconfirm xorg-server qtile alacritty rofi feh

# 🎯 Done!
EOF

echo "✅ Installation complete! Reboot now."
