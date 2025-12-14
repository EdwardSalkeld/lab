# Debian 12 (Bookworm) - Oldstable
resource "proxmox_virtual_environment_download_file" "debian_12_lxc" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve"

  url = "http://download.proxmox.com/images/system/debian-12-standard_12.2-1_amd64.tar.zst"

  # Allow Terraform to manage files that already exist
  overwrite_unmanaged = true

  upload_timeout = 600
}

# Debian 13 (Trixie) - Stable (became stable August 2024)
resource "proxmox_virtual_environment_download_file" "debian_13_lxc" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve"

  url = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"

  # Allow Terraform to manage files that already exist
  overwrite_unmanaged = true

  upload_timeout = 600
}

# Debian 14 (Forky) - Testing
# Proxmox LXC templates for Debian 14 are not yet available.

# Talos Linux v1.11.5 - nocloud ISO with qemu-guest-agent
resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"

  # Using factory.talos.dev with custom schematic for qemu-guest-agent
  # Schematic ID: 376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba
  # Using .iso for bootable CDROM
  url       = "https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.11.5/nocloud-amd64.iso"
  file_name = "talos-v1.11.5-nocloud-amd64.iso"

  overwrite_unmanaged = true
  upload_timeout      = 1800
}
