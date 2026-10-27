# Dedicated Debian application guest; PostgreSQL remains on Partridge.
resource "proxmox_virtual_environment_download_file" "zulip_debian" {
  provider           = proxmox.luna
  node_name          = var.luna_proxmox_node_name
  datastore_id       = var.proxmox_iso_datastore_id
  content_type       = "import"
  file_name          = "debian-13-genericcloud-amd64-20261026-2643.qcow2"
  url                = "https://cloud.debian.org/images/cloud/trixie/20261026-2643/debian-13-genericcloud-amd64-20261026-2643.qcow2"
  checksum_algorithm = "sha512"
  checksum           = "3ace18e33bdd036edb49d1f79342bd01d2ab980e35194edb0b410435cd543538d286a0bd13bbb0835f7862306e3d385ce2f6a70d8ecf0bd961111166adbc1b8e"
}

resource "proxmox_virtual_environment_vm" "zulip" {
  provider    = proxmox.luna
  name        = "zulip-vm"
  description = "Debian 13 Zulip application host; database and backups on Partridge."
  node_name   = var.luna_proxmox_node_name
  tags        = ["debian", "zulip", "luna"]
  on_boot     = true
  started     = true
  bios        = "seabios"
  boot_order  = ["virtio0"]

  # Enabled after scripts/zulip-bootstrap.sh installs the agent. Avoid waiting
  # for a nonexistent agent during the initial cloud-image bootstrap.
  agent { enabled = false }
  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }
  memory { dedicated = 3072 }
  network_device { bridge = var.proxmox_network_bridge }
  disk {
    datastore_id = var.luna_vm_datastore_id
    interface    = "virtio0"
    file_id      = proxmox_virtual_environment_download_file.zulip_debian.id
    size         = 40
    discard      = "on"
    iothread     = true
    serial       = "zulip-root"
  }
  initialization {
    datastore_id = var.luna_vm_datastore_id
    dns { domain = "int.alcachofa.faith" }
    ip_config {
      ipv4 { address = "dhcp" }
    }
    user_account {
      username = "billy"
      keys     = concat(var.billy_public_ssh_keys, var.public_ssh_keys)
    }
  }
  serial_device {}
  vga { type = "serial0" }
  operating_system { type = "l26" }
  lifecycle { prevent_destroy = true }
}

output "zulip_vm_id" {
  value       = proxmox_virtual_environment_vm.zulip.vm_id
  description = "Persistent Zulip Debian VM on Luna; application bootstrap is a separate step."
}
