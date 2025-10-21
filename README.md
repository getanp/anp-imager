# ANP-Imager

A **stand-alone Linux-based imaging system** that runs entirely from RAM.  
Boot it over **PXE** or from a **USB stick**, and it provides a menu-driven interface to capture or restore system images automatically.

---

## Features

- **PXE or USB boot** — no OS or disk required
  
- **Completely RAM-resident** — safe, fast, and clean
  
- **Automatic device discovery** via `udevd`
  
- **Interactive TUI** with `whiptail` menus
  
- **NFS-based image repository** (optional)
  
- **Supports multiple formats**: `.img`, `.vdi`, `.qcow2`, `.vmdk`
  
- **Auto power-off or manual shell access** after completion
  

---

## System Architecture

| Stage | Component | Purpose |
| --- | --- | --- |
| **1. Boot** | PXE or USB loads the Linux kernel + custom `initrd.img`. |     |
| **2. Kernel** | Unpacks the initramfs and runs `/init` as PID 1. |     |
| **3. `/init`** | Mounts `/proc`, `/sys`, `/dev`; starts `udevd`; creates ttys; launches the imaging app. |     |
| **4. `imager-init`** | User interface — detects disks, manages NFS mount, handles capture/restore. |     |
| **5. Imaging Tools** | `qemu-img`, `zstd`, and NFS utilities perform actual imaging operations. |     |
| **6. Exit** | Clean power-off or shell for diagnostics. |     |

## Safety Notes

- Runs entirely in RAM – no changes made to host disks until confirmed.
  
- `/dev/mem`, `/dev/kmem`, and `/dev/port` are created root-only (`0600`).
  
- Syncs all writes before power-off.
  

---

## Result

- Boots from **PXE or USB**
  
- No installed OS required
  
- Automatically detects disks and networks
  
- Provides menu-driven capture / restore
  
- Shuts down cleanly when done
  
---
Quick Install Debian 13

```bash
sh scripts/install.sh
```

Continue with step 4

---

Installation (Manual)
1. Copy required directories

From the project repository root:

```bash
# Copy the imaging scripts into the system root
sudo cp -r scripts/* /

# Copy PXE boot files into the TFTP directory
sudo mkdir -p /srv/tftp
sudo cp -r boot_files/* /srv/tftp/
```

This installs all initramfs-hooks, system binaries (/usr/local/sbin/imager-init, imager-restore, etc.),
and PXE assets (vmlinuz, initrd.img, PXE menus).


3. Build the PXE initrd

Rebuild the initramfs (and copy your kernel) so the custom /init and imaging tools are embedded:
```bash
sudo mkinitramfs -o /srv/tftp/initrd.img "$(uname -r)"
sudo cp /boot/vmlinuz-$(uname -r) /srv/tftp/vmlinuz
```

4. Install VirtualBox (If you want to manage the VMs)
```bash
wget https://download.virtualbox.org/virtualbox/7.2.4/virtualbox-7.2_7.2.4-170995~Debian~trixie_amd64.deb
apt install build-essential linux-headers-`uname -r` linux-headers-amd64
dpkg -i virtualbox-7.2_7.2.4-170995~Debian~trixie_amd64.deb
usermod -a -G vboxusers <yourusername>

```


5. Setup NFS for the images
```bash
mkdir /srv/images
groupadd imager
usermod -a -G imager <yourusername>
chgrp -R imager /srv/images
chmod -R 777 /srv/images
echo /srv/images *(rw,sync,no_subtree_check,fsid=0,crossmnt) >> /etc/exports
exportfs -ra
```

6. Setup the PXE enviroment
```bash
nano /srv/tftp/grub/grub.cfg
```
Find the line:
img_nfs=x.x.x.x
replace it with the ip of your image computer (same computer that has the nfs on it)
```bash
img_nfs=192.168.1.50:/srv/images
```

7. Create a USB Boot Device (optional if you don't want to use PXE)

A helper script is provided:
```bash
usb/linux/create.sh
```


---
### © 2025 Advanced Network Professionals

Built for fast, consistent deployment and recovery across workstations and servers.

