resource "proxmox_virtual_environment_vm" "kite" {
  count = var.enable_kite_vm ? 1 : 0

  name        = var.kite_vm_name
  description = "NixOS media VM for Jellyfin and Navidrome on luna."
  node_name   = var.luna_proxmox_node_name
  tags        = ["nixos", "media", "luna"]

  bios          = "ovmf"
  boot_order    = ["scsi0"]
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  # Installer-stage VMs cannot service Proxmox guest-agent reboot requests.
  reboot_after_update = false
  started             = true

  cpu {
    cores = var.kite_vm_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.kite_vm_memory
  }

  network_device {
    bridge = var.proxmox_network_bridge
  }

  efi_disk {
    datastore_id = var.luna_vm_datastore_id
  }

  disk {
    datastore_id = var.luna_vm_datastore_id
    interface    = "scsi0"
    size         = var.kite_root_disk_size
    discard      = "on"
    iothread     = true
    serial       = "kite-root"
  }

  disk {
    datastore_id = var.luna_vm_datastore_id
    interface    = "scsi1"
    size         = var.kite_jellyfin_disk_size
    discard      = "on"
    iothread     = true
    serial       = "kite-jellyfin"
  }

  disk {
    datastore_id = var.luna_vm_datastore_id
    interface    = "scsi2"
    size         = var.kite_navidrome_disk_size
    discard      = "on"
    iothread     = true
    serial       = "kite-navidrome"
  }

  cdrom {
    file_id   = proxmox_virtual_environment_download_file.nixos_minimal_iso.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
  }
}
