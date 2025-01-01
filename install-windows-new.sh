#!/bin/bash

# Update and install necessary packages
apt update -y && apt upgrade -y
apt install grub2 wimtools ntfs-3g -y

# Get the disk size in GB and convert to MB
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))

# Calculate partition sizes (25% each for boot and installer, remaining for installation)
part_size_mb=$((disk_size_mb / 4))

# Create GPT partition table
parted /dev/sda --script -- mklabel gpt

# Create three partitions
parted /dev/sda --script -- mkpart primary ntfs 1MB ${part_size_mb}MB           # Reserved for Windows installation
parted /dev/sda --script -- mkpart primary ntfs ${part_size_mb}MB $((2 * part_size_mb))MB  # For GRUB bootloader
parted /dev/sda --script -- mkpart primary ntfs $((2 * part_size_mb))MB $((3 * part_size_mb))MB  # For Windows installer files

# Inform kernel of partition table changes
partprobe /dev/sda
sleep 5  # Allow the system to recognize the changes

# Format the partitions
mkfs.ntfs -f /dev/sda1  # Reserved for Windows installation
mkfs.ntfs -f /dev/sda2  # GRUB bootloader
mkfs.ntfs -f /dev/sda3  # Windows installer files

echo "NTFS partitions created"

# Install GRUB on the second partition
mount /dev/sda2 /mnt
grub-install --root-directory=/mnt /dev/sda

# Create and configure GRUB bootloader
cd /mnt/boot/grub
cat <<EOF > grub.cfg
menuentry "Windows Installer" {
    insmod ntfs
    search --set=root --file=/bootmgr
    ntldr /bootmgr
    boot
}
EOF

# Prepare directory for Windows installer files
cd ~
mkdir windisk
mount /dev/sda3 windisk

# Download and mount the Windows ISO
wget -O win10.iso --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso
mkdir winfile
mount -o loop win10.iso winfile

# Copy Windows installation files to the third partition
rsync -avz --progress winfile/* /dev/sda3

# Unmount the ISO
umount winfile

# Download and integrate VirtIO drivers
wget -O virtio.iso https://bit.ly/4d1g7Ht
mount -o loop virtio.iso winfile
mkdir /mnt/sources/virtio
rsync -avz --progress winfile/* /mnt/sources/virtio

# Update Windows boot image with VirtIO drivers
cd /mnt/sources
touch cmd.txt
echo 'add virtio /virtio_drivers' >> cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt

# Cleanup and reboot
umount /mnt
reboot
