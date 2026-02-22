resource "proxmox_virtual_environment_container" "this" {
  description = var.description

  node_name = var.node_name
  vm_id     = var.vm_id

  # Increase timeouts for all operations
  timeout_create = var.timeout_create
  timeout_update = var.timeout_update
  timeout_delete = var.timeout_delete

  # newer linux distributions require unprivileged user namespaces
  unprivileged = var.unprivileged

  features {
    nesting = var.features_nesting
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ipv4_address
      }
    }

    user_account {
      # Configures root user with SSH key and password
      keys     = var.ssh_keys
      password = var.root_password
    }
  }

  network_interface {
    name = var.network_interface_name
  }

  disk {
    datastore_id = var.disk_datastore_id
    size         = var.disk_size
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = var.os_type
  }

  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      volume = mount_point.value.volume
      size   = lookup(mount_point.value, "size", null)
      path   = mount_point.value.path
    }
  }

  startup {
    order      = var.startup_order
    up_delay   = var.startup_up_delay
    down_delay = var.startup_down_delay
  }
}

resource "random_password" "container_password" {
  length           = 24
  override_special = "_%@"
  special          = true
}
