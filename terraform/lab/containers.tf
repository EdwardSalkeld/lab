# Debian 12 (Bookworm) - Oldstable
module "debian_12_container" {
  source = "./modules/lxc-container"

  node_name = "sol"
  hostname  = "debian-12-oldstable"

  template_file_id = proxmox_virtual_environment_download_file.debian_12_lxc.id
  os_type          = "debian"

  ssh_keys      = var.public_ssh_keys
  root_password = random_password.debian_12_password.result

  mount_points = [
    {
      volume = "local-lvm"
      size   = "10G"
      path   = "/mnt/volume"
    }
  ]
}

resource "random_password" "debian_12_password" {
  length           = 16
  override_special = "_%@"
  special          = true
}

# Debian 13 (Trixie) - Stable
module "debian_13_container" {
  source = "./modules/lxc-container"

  node_name = "sol"
  hostname  = "debian-13-stable"

  template_file_id = proxmox_virtual_environment_download_file.debian_13_lxc.id
  os_type          = "debian"

  ssh_keys      = var.public_ssh_keys
  root_password = random_password.debian_13_password.result

  mount_points = [
    {
      volume = "local-lvm"
      size   = "10G"
      path   = "/mnt/volume"
    }
  ]
}

resource "random_password" "debian_13_password" {
  length           = 16
  override_special = "_%@"
  special          = true
}
