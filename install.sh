#!/bin/bash

set -e  # Exit script immediately on any error

# Configurable Variables
DISK="/dev/nvme0n1"   # Adjust as needed
HOSTNAME="archlinux"
USERNAME="user"
PASSWORD="password"  # CHANGE THIS AFTER INSTALLATION!

echo "⚡ Arch Linux Installation - Btrfs + Encryption + ZRAM + Timeshift + Qtile ⚡"

# 1️⃣ Set Timezone & Update Mirrors
echo "[+] Setting timezone..."
timedatectl set-timezone America/New_York

echo "[+] Updating mirrorlist..."
reflector -c US --verbose -l 15 -n 5 -p http --sort rate --save /etc/pacman.d/mirrorlist

# 2️⃣ Disk Partitioning (UEFI)
echo "[+] Partitioning $DISK..."
wipefs --all --force "$DISK"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 512MiB 100%

# 3️⃣ LUKS Encryption Setup
echo "[+] Configuring LUKS encryption..."
cryptsetup luksFormat "${DISK}p2"
cryptsetup open "${DISK}p2" main

# 4️⃣ Formatting Partitions
echo "[+] Formatting partitions..."
mkfs.fat -F32 "${DISK}p1"
mkfs.btrfs -f /dev/mapper/main

# 5️⃣ Creating Btrfs Subvolumes
echo "[+] Creating Btrfs subvolumes..."
mount /dev/mapper/main /mnt
for subvol in @ @home @var @snapshots; do
    btrfs subvolume create "/mnt/$subvol"
done
umount /mnt

# 6️⃣ Mounting Btrfs Subvolumes
echo "[+] Mounting subvolumes..."
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
mkdir -p /mnt/{boot,home,var,.snapshots}
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@var /dev/mapper/main /mnt/var
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@snapshots /dev/mapper/main /mnt/.snapshots
mount "${DISK}p1" /mnt/boot

# 7️⃣ Install Base System
echo "[+] Installing base system..."
pacstrap /mnt --noconfirm base-devel linux-lts linux-lts-headers linux-firmware \
pipewire alsa-utils pipewire-pulse pipewire-jack sudo nano openssh zram-generator \
firewalld reflector 

# 8️⃣ Generate fstab
echo "[+] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# 9️⃣ Configure System Inside Chroot
echo "[+] Configuring system inside chroot..."
arch-chroot /mnt /bin/bash <<EOF
set -e  # Exit on error

echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/\$(curl -s https://ipapi.co/timezone) /etc/localtime
hwclock --systohc
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "127.0.1.1   $HOSTNAME" >> /etc/hosts

# 🔥 Install Bootloader (GRUB)
echo "[+] Installing GRUB..."
pacman -Sy --noconfirm grub efibootmgr mtools dosfstools btrfs-progs grub-btrfs networkmanager network-manager-applet
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
echo 'GRUB_CMDLINE_LINUX="cryptdevice=${DISK}p2:main root=/dev/mapper/main"' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P

# 🏠 Create User & Set Passwords
echo "[+] Creating user: $USERNAME"
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# 🚀 ZRAM Setup
echo "[+] Configuring ZRAM..."
echo "zram" > /etc/modules-load.d/zram.conf
echo "options zram num_devices=1" > /etc/modprobe.d/zram.conf
echo 'KERNEL=="zram0", ATTR{disksize}="2G", RUN+="/sbin/mkswap /dev/zram0", TAG+="systemd"' > /etc/udev/rules.d/99-zram.rules
echo "/dev/zram0 none swap sw 0 0" >> /etc/fstab

# 🛠 Install Additional Packages
echo "[+] Installing utilities..."
pacman -Sy --noconfirm timeshift openssh nemo ipset acpid man-db \
man-pages texinfo sof-firmware ttf-firacode-nerd alacritty bolt dfu-util libusb glib2-devel 

# 🎨 Install Qtile & Display Manager
echo "[+] Installing Qtile & display manager..."
pacman -Sy --noconfirm bluez bluez-utils intel-ucode lightdm lightdm-gtk-greeter xorg-server qtile alacritty rofi feh

# 🛡 Enable Essential Services
echo "[+] Enabling system services..."
for service in NetworkManager bluetooth sshd firewalld reflector.timer fstrim.timer acpid; do
    systemctl enable "\$service"
done

echo "[✅] Installation completed inside chroot!"
EOF

echo "✅ Installation complete! You may now reboot."
