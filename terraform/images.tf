# Debian 13 (Trixie) - Stable (became stable August 2024)
resource "proxmox_virtual_environment_download_file" "debian_13_lxc" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "sol"

  url = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"

  # Allow Terraform to manage files that already exist
  overwrite_unmanaged = true

  upload_timeout = 600
}

# Debian 14 (Forky) - Testing
# Proxmox LXC templates for Debian 14 are not yet available.

locals {
  talos_upgrade_version = "v1.12.3"
  talos_qemu_schematic = {
    customization = {
      systemExtensions = {
        officialExtensions = ["siderolabs/qemu-guest-agent"]
      }
    }
  }
}

resource "talos_image_factory_schematic" "qemu_guest_agent" {
  schematic = yamlencode(local.talos_qemu_schematic)
}

# Talos Linux v1.11.5 - nocloud ISO with qemu-guest-agent
resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "sol"

  # Using factory.talos.dev with custom schematic for qemu-guest-agent
  # Schematic ID: ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
  # Using .iso for bootable CDROM
  url       = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.11.5/nocloud-amd64.iso"
  file_name = "talos-v1.11.5-nocloud-amd64.iso"

  overwrite_unmanaged = true
  upload_timeout      = 1800
}

# Talos Linux upgrade target - nocloud ISO with qemu-guest-agent
resource "proxmox_virtual_environment_download_file" "talos_nocloud_image_v1_12_2_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "sol"

  # Schematic is managed by Terraform via talos_image_factory_schematic.qemu_guest_agent
  url       = "https://factory.talos.dev/image/${talos_image_factory_schematic.qemu_guest_agent.id}/${local.talos_upgrade_version}/nocloud-amd64.iso"
  file_name = "talos-${local.talos_upgrade_version}-nocloud-amd64.iso"

  overwrite_unmanaged = true
  upload_timeout      = 1800
}

# Talos Linux upgrade target - nocloud raw disk image with qemu-guest-agent
resource "proxmox_virtual_environment_download_file" "talos_nocloud_image_v1_12_2_raw" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "sol"

  # Schematic is managed by Terraform via talos_image_factory_schematic.qemu_guest_agent
  url                     = "https://factory.talos.dev/image/${talos_image_factory_schematic.qemu_guest_agent.id}/${local.talos_upgrade_version}/nocloud-amd64.raw.zst"
  file_name               = "talos-${local.talos_upgrade_version}-nocloud-amd64.img"
  decompression_algorithm = "zst"

  overwrite_unmanaged = true
  upload_timeout      = 1800
}
resource "proxmox_virtual_environment_download_file" "talos_nocloud_image2" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "sol"

  # Using factory.talos.dev with custom schematic for qemu-guest-agent
  # Schematic ID: ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
  # Using .iso for bootable CDROM
  url                     = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.11.5/nocloud-amd64.raw.zst"
  file_name               = "talos-v1.11.5-nocloud-amd64.img"
  decompression_algorithm = "zst"

  overwrite_unmanaged = true
  upload_timeout      = 1800
}
