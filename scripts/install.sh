#!/bin/sh
apt update
apt install qemu-utils nfs-common whiptail iw net-tools dmidecode pv wpasupplicant grub-efi-amd64-bin grub-efi-amd64-signed nfs-kernel-server tftpd-hpa
cp -r scripts/usr/* /usr/
cp -r scripts/etc/* /etc/
cp -r scripts/srv/* /srv/
mkdir -p /srv/tftp
cp -r boot_files/* /srv/tftp/
mkinitramfs -o /srv/tftp/initrd.img "$(uname -r)"
cp /boot/vmlinuz-$(uname -r) /srv/tftp/vmlinuz

mkdir /srv/images
groupadd imager
usermod -a -G imager <yourusername>
chgrp -R imager /srv/images
chmod -R 777 /srv/images
echo /srv/images *(rw,sync,no_subtree_check,fsid=0,crossmnt) >> /etc/exports
exportfs -ra
