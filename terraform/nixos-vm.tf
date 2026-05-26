resource "proxmox_virtual_environment_download_file" "nixos_minimal_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_iso_datastore_id
  node_name    = var.proxmox_node_name

  url       = "https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-x86_64-linux.iso"
  file_name = "nixos-25.11-minimal-x86_64-linux.iso"

  overwrite_unmanaged = true
  upload_timeout      = 1800
}

resource "proxmox_virtual_environment_vm" "nixos_01" {
  name        = var.nixos_vm_name
  description = "First NixOS learning VM. Boot from ISO and install manually."
  node_name   = var.proxmox_node_name
  tags        = ["nixos", "learning"]

  bios       = "ovmf"
  boot_order = ["scsi0", "ide2"]
  on_boot    = true
  started    = true

  agent {
    enabled = false
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  network_device {
    bridge = var.proxmox_network_bridge
  }

  efi_disk {
    datastore_id = var.proxmox_vm_datastore_id
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    interface    = "scsi0"
    size         = var.nixos_vm_disk_size
    discard      = "on"
    iothread     = true
  }

  cdrom {
    file_id   = proxmox_virtual_environment_download_file.nixos_minimal_iso.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "partridge" {
  name        = var.partridge_vm_name
  description = "First repo-managed NixOS VM."
  node_name   = var.proxmox_node_name
  tags        = ["bird", "nixos", "prod"]

  bios       = "ovmf"
  boot_order = ["ide2", "scsi0"]
  on_boot    = true
  started    = true

  agent {
    enabled = false
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  network_device {
    bridge = var.proxmox_network_bridge
  }

  efi_disk {
    datastore_id = var.proxmox_vm_datastore_id
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    interface    = "scsi0"
    size         = var.nixos_vm_disk_size
    discard      = "on"
    iothread     = true
  }

  cdrom {
    file_id   = proxmox_virtual_environment_download_file.nixos_minimal_iso.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }
}
