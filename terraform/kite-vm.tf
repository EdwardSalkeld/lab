resource "proxmox_virtual_environment_vm" "kite" {
  count    = var.enable_kite_vm ? 1 : 0
  provider = proxmox.luna

  name        = var.kite_vm_name
  description = "NixOS media VM for Jellyfin, Navidrome, and MCM on standalone luna."
  node_name   = var.luna_proxmox_node_name
  tags        = ["nixos", "media", "luna"]

  bios                = "ovmf"
  boot_order          = ["scsi0"]
  on_boot             = true
  scsi_hardware       = "virtio-scsi-single"
  reboot_after_update = false
  started             = true

  agent {
    enabled = true
  }

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

  disk {
    datastore_id = var.luna_vm_datastore_id
    interface    = "scsi3"
    size         = var.kite_wantlist_disk_size
    discard      = "on"
    iothread     = true
    serial       = "kite-wantlist"
  }

  cdrom {
    file_id   = "none"
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    # scsi4 and scsi5 are manually attached raw host devices. Proxmox permits
    # arbitrary host paths only for literal root@pam, not Terraform's API
    # token, so their documented recreation is outside Terraform.
    #
    # The provider treats otherwise unmodelled disks as removable, so retain
    # this guard to prevent plans from detaching the two external disks.
    ignore_changes = [disk]

    precondition {
      condition     = var.LUNA_PROXMOXENDPOINT != null && var.LUNA_PROXMOXTOKEN != null
      error_message = "Set LUNA_PROXMOXENDPOINT and LUNA_PROXMOXTOKEN before enabling kite on standalone luna."
    }
  }
}
