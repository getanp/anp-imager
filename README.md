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

Installation
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

2. Build the PXE initrd

Rebuild the initramfs so the custom /init and imaging tools are embedded:
```bash
sudo mkinitramfs -o /srv/tftp/initrd.img "$(uname -r)"
```

3. Create a USB Boot Device

A helper script is provided:
```bash
usb/linux/create.sh
```

---
### © 2025 Advanced Network Professionals

Built for fast, consistent deployment and recovery across workstations and servers.
