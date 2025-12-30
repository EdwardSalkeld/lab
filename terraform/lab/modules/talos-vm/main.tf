terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}
resource "proxmox_virtual_environment_vm" "talos" {
  name        = var.name
  description = var.description
  node_name   = var.node_name

  # Use OVMF (UEFI) - Talos works better with UEFI
  bios = "ovmf"

  agent {
    enabled = true
    wait_for_ip {
      ipv4 = true
    }
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory
  }

  network_device {
    bridge = var.network_bridge
  }

  # EFI disk required for OVMF
  efi_disk {
    datastore_id = var.datastore_id
  }

  # Disk for Talos to install to
  disk {
    file_id     = var.iso_file_id
    file_format = "raw"
    interface   = "virtio0"
    size        = 20
  }

  operating_system {
    type = "l26" # Linux 2.6+ kernel
  }

  on_boot = var.on_boot

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
      ipv6 {
        address = "dhcp"
      }
    }
  }
}
