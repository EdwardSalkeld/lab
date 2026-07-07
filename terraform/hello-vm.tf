resource "proxmox_virtual_environment_download_file" "debian_12_genericcloud" {
  content_type = "import"
  datastore_id = var.proxmox_iso_datastore_id
  node_name    = var.proxmox_node_name

  url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  file_name = "debian-12-genericcloud-amd64.qcow2"
}

resource "proxmox_virtual_environment_vm" "hello" {
  name        = var.hello_vm_name
  description = "Zero-touch bootstrap VM for remote infra exercises."
  node_name   = var.proxmox_node_name
  tags        = ["bird", "bootstrap", "debian", "hello"]

  bios                = "ovmf"
  boot_order          = ["scsi0"]
  on_boot             = true
  reboot_after_update = true
  scsi_hardware       = "virtio-scsi-single"
  started             = true

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.hello_memory_mb
  }

  initialization {
    datastore_id = var.proxmox_vm_datastore_id

    dns {
      servers = var.hello_dns_servers
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # Use root deliberately for the bootstrap phase so the follow-up automation
    # can complete without depending on distro-specific sudo defaults.
    user_account {
      username = "root"
      keys = concat(
        var.billy_public_ssh_keys,
        var.public_ssh_keys,
        var.hello_bootstrap_public_ssh_keys,
      )
    }
  }

  network_device {
    bridge = var.proxmox_network_bridge
  }

  efi_disk {
    datastore_id = var.proxmox_vm_datastore_id
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    import_from  = proxmox_virtual_environment_download_file.debian_12_genericcloud.id
    interface    = "scsi0"
    size         = var.hello_root_disk_size
    discard      = "on"
    iothread     = true
    serial       = "${var.hello_vm_name}-root"
  }

  operating_system {
    type = "l26"
  }
}
