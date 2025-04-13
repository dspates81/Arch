#!/bin/bash

# Update mirrorlist
reflector -a 6 --sort rate --latest 5 --protocol https --country US --save /etc/pacman.d/mirrorlist

# Enable NTP
timedatectl set-ntp true

# Automated partitioning
(
echo n # Add a new partition
echo p # Primary partition
echo 1 # Partition number 1
echo   # Default - start at beginning of disk
echo +600M # 600MB boot partition
echo t # Change partition type
echo 1 # EFI System

echo n # Add a new partition
echo p # Primary partition
echo 2 # Partition number 2
echo   # Default - start at beginning of disk
echo +9G # 9GB swap partition
echo t # Change partition type
echo 19 # Linux swap

echo n # Add a new partition
echo p # Primary partition
echo 3 # Partition number 3
echo   # Default - start at beginning of disk
echo   # Default - extend to end of disk
echo w # Write changes
) | fdisk /dev/nvme0n1

# Format partitions
mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
mkswap -L swap /dev/nvme0n1p2
swapon /dev/nvme0n1p2
mkfs.btrfs -L Root /dev/nvme0n1p3 -f

# Format additional drives for server
mkfs.btrfs -L Data /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg /dev/sdh /dev/sdi -f

# Mount and create subvolumes
mount /dev/nvme0n1p3 /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@var
btrfs su cr /mnt/@snapshots
umount /mnt

# Mount subvolumes
mount -o noatime,compress=zstd,space_cache=v2,subvol=@ /dev/nvme0n1p3 /mnt
mkdir -p /mnt/{boot/efi,home,var,.snapshots,Vault}
mount -o noatime,compress=zstd,space_cache=v2,subvol=@home /dev/nvme0n1p3 /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,subvol=@var /dev/nvme0n1p3 /mnt/var
mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots /dev/nvme0n1p3 /mnt/.snapshots

# Mount additional drives
mount /dev/sdb /mnt
btrfs su cr /mnt/@Vault
mount -o noatime,compress=zstd,space_cache=v2,subvol=@Vault /dev/sdb /mnt/Vault
# Mount EFI partition
mount /dev/nvme0n1p1 /mnt/boot/efi

# Install base system
pacstrap /mnt base linux linux-firmware btrfs-progs snapper nano git wget reflector

# Generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Chroot into new system
arch-chroot /mnt

# Set timezone and locale
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

# Set hostname and hosts
echo "filesys" >> /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 filesys.localdomain filesys" >> /etc/hosts

# Display hosts file
cat /etc/hosts

# Install additional packages
pacman -S --needed \
grub grub-btrfs efibootmgr networkmanager network-manager-applet mtools nfs-utils nss-mdns ntfs-3g openssh \
btrfs-progs acpi acpi_call acpid avahi rsync \
base-devel bluez bluez-utils cups dialog dnsutils dosfstools \
gvfs gvfs-smb hplip inetutils linux-headers \
pipewire pipewire-alsa pipewire-jack pipewire-pulse alsa-firmware alsa-plugins alsa-utils \
terminus-font tlp wpa_supplicant xdg-user-dirs xdg-utils zsh grml-zsh-config \
gedit rofi gnome-disk-utility nemo terminator samba fastfetch inotify-tools \
git intel-ucode wireless_tools wpa_supplicant mtools dosfstools

# Enable services
systemctl enable NetworkManager
systemctl enable reflector.timer
systemctl enable sshd
systemctl enable acpid
systemctl enable avahi-daemon
systemctl enable bluetooth
systemctl enable cups
systemctl enable fstrim.timer
systemctl enable tlp
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# Create user and set password
useradd -mU -s /bin/zsh -G sys,log,network,scanner,power,rfkill,users,video,storage,optical,lp,audio,wheel,adm justin
passwd justin
EDITOR=nano visudo

# Install and configure GRUB
grub-install --removable --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Server
mkinitcpio -p linux
grub-mkconfig -o /boot/grub/grub.cfg

