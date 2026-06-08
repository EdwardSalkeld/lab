resource "proxmox_virtual_environment_download_file" "nixos_minimal_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_iso_datastore_id
  node_name    = var.proxmox_node_name

  url       = "https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-x86_64-linux.iso"
  file_name = "nixos-25.11-minimal-x86_64-linux.iso"

  overwrite_unmanaged = true
  upload_timeout      = 1800
}

resource "proxmox_virtual_environment_vm" "partridge" {
  name        = var.partridge_vm_name
  description = "First repo-managed NixOS VM."
  node_name   = var.proxmox_node_name
  tags        = ["bird", "nixos", "prod"]

  bios       = "ovmf"
  boot_order = ["scsi0"]
  on_boot    = true
  started    = true

  agent {
    enabled = true
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
    size         = var.partridge_root_disk_size
    discard      = "on"
    iothread     = true
    serial       = "partridge-root"
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    interface    = "scsi1"
    size         = var.partridge_code_disk_size
    discard      = "on"
    iothread     = true
    serial       = "partridge-code"
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    interface    = "scsi2"
    size         = var.partridge_postgres_disk_size
    discard      = "on"
    iothread     = true
    serial       = "partridge-postgres"
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    interface    = "scsi3"
    size         = var.partridge_vaultwarden_disk_size
    discard      = "on"
    iothread     = true
    serial       = "vaultwarden"
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    interface    = "scsi4"
    size         = var.partridge_prometheus_disk_size
    discard      = "on"
    iothread     = true
    serial       = "prometheus"
  }

  cdrom {
    file_id   = proxmox_virtual_environment_download_file.nixos_minimal_iso.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "magpie" {
  name        = var.magpie_vm_name
  description = "Repo-managed disposable NixOS development VM."
  node_name   = var.proxmox_node_name
  tags        = ["bird", "nixos", "dev"]

  bios          = "ovmf"
  boot_order    = ["ide2", "scsi0"]
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  # Installer-stage VMs cannot service Proxmox guest-agent reboot requests.
  reboot_after_update = false
  started             = true

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
    size         = var.magpie_root_disk_size
    discard      = "on"
    iothread     = true
    serial       = "magpie-root"
  }

  cdrom {
    file_id   = proxmox_virtual_environment_download_file.nixos_minimal_iso.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }
}
