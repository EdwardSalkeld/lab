# Isolated test target for disruptive Chatting changes. This container is
# deliberately separate from the production Magpie VM and its data.
resource "proxmox_virtual_environment_container" "sparrow" {
  node_name     = var.proxmox_node_name
  vm_id         = 76300
  description   = "Debian test host for the Chatting roadmap branch."
  tags          = ["bird", "chatting", "test"]
  started       = true
  start_on_boot = true
  unprivileged  = true

  features {
    nesting = true
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 4096
    swap      = 1024
  }

  disk {
    datastore_id = var.proxmox_vm_datastore_id
    size         = 24
  }

  network_interface {
    name   = "eth0"
    bridge = var.proxmox_network_bridge
  }

  initialization {
    hostname = "sparrow"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      # Root inside the container has key-based SSH access for Edward and Billy.
      keys = concat(var.public_ssh_keys, var.billy_public_ssh_keys)
    }
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    type             = "debian"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Sparrow was brought up on sol to verify guest access and the first deployment
# before this PR is merged. Adopt that exact CT into the Lab Terraform state.
import {
  to = proxmox_virtual_environment_container.sparrow
  id = "sol/76300"
}
