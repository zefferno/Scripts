#!/bin/bash
#===================================================================================
#
# FILE: ArchLinux-setup.sh
#
# DESCRIPTION: Automation for do-it-yourself installation of ArchLinux
# 
# TESTED ON: ArchLinux 4.0
#
# AUTHOR: Mor Kalfon, zefferno@gmail.com
#===================================================================================

set -o nounset


#----------------------------------------------------------------------
# Global variables
#----------------------------------------------------------------------
TARGET_DISK_DEV = "/dev/sda"
BOOT_SIZE = "200M"
SWAP_SIZE = "$(free | awk '/^Mem:/{print int($2/1024*2)}')M"
MIRROR_SERVER = "http://mirror.isoc.org.il/pub/archlinux/$repo/os/$arch"
HOSTNAME = "LinZi"
LOGO = "\e[92+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+\n
        \e[37m VM ArchLinux Setup Automation
        \e[92+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+\n"


#=== FUNCTION ================================================================
# NAME: set_comment_in_file
# DESCRIPTION: Un/Comment a value in a given file.
# PARAMETER 1: True for comment, False for uncomment
# PARAMETER 2: value to change
# PARAMETER 3: file to handle
#=============================================================================
set_comment_in_file() {
  local option=$1
  local value=$2
  local file=$3

  if [[$option == true]]; then
  	sed -i "s/^\(${value}.*\)$/#\1/" "${file}"
  elif [[$option == false]]; then
    sed -i "s/^#\(${value}.*\)$/\1/" "${file}"
  fi
}

#=== FUNCTION ================================================================
# NAME: print_error
# DESCRIPTION: Prints script error and exit (optionally)
# PARAMETER 1: Error to print
# PARAMETER 2: Do not exit afterwards? (boolean)
#=============================================================================
print_error() {
  echo "ERROR: $1"
  if [[$2]]; then
  else
    exit -1
  fi
}


#----------------------------------------------------------------------
# Main
#----------------------------------------------------------------------

# PREREQUISITE: Check Internet availablity
if [ $(wget -q --spider http://www.google.com) -eq 0 ]; then
  print_error "Your internet connection is down.\nPlease check your network settings."
fi

# Print script logo
echo -e $LOGO

# Disk partition setup
echo "Wiping GPT and MBR structures..."
sgdisk -Z $TARGET_DISK_DEV
echo "Creating partitions..."
sgdisk -a 2048 $TARGET_DISK_DEV
sgdisk -n 1:0:+$BOOT_SIZE -c 1:"BOOT" -t:ef00 $TARGET_DISK_DEV
sgdisk -n 2:0:+$SWAP_SIZE -c 2:"SWAP" -t:8200 $TARGET_DISK_DEV
sgdisk -n 3:0:0 -c 3:"ROOT" -t:8300 $TARGET_DISK_DEV
echo "Formatting partitions..."
# BOOT partition
mkfs.vfat ${TARGET_DISK_DEV}1
# SWAP partition
mkswap ${TARGET_DISK_DEV}2
swapon ${TARGET_DISK_DEV}2
# ROOT partition
mkfs.ext4 $(TARGET_DISK_DEV)3

echo "Mounting partitions..."
mount /dev/sda3 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
 
echo "Configuring Pacman mirror..."
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
echo "Server = $MIRROR_SERVER" > /etc/pacman.d/mirrorlist

echo "Refreshing package lists..."
pacman -Syu
 
echo "Installing ArchLinux..."
pacstrap -i /mnt base base-devel

echo "Configuring ArchLinux..."
genfstab -L -p /mnt >> /mnt/etc/fstab

# Chroot to the new installation
arch-chroot /mnt /bin/bash

# Configure locales
uncomment_value_in_file en_US /etc/locale.gen
uncomment_value_in_file he_IL /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
export LANG=en_US.UTF-8

# Setup TimeZone
ln -s /usr/share/zoneinfo/Israel /etc/localtime
hwclock --systohc --utc

# Setup hostname
echo $HOSTNAME > /etc/hostname

# Save resolved DNS's
cp /etc/resolv.conf /etc/resolv.conf
sed -i '/^127.0.0.1/ s/$/\t'"$HOSTNAME"'/' /etc/hosts


swapoff -a
umount /mnt/

echo "Setup completed! Please reboot."
