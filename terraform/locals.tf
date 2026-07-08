locals {
  wren_replace_signature = {
    bios             = "seabios"
    disk_interface   = "virtio0"
    root_disk_serial = "${var.hello_vm_name}-root"
    scsi_hardware    = "virtio-scsi-pci"
    serial_console   = true
    vga_type         = "serial0"
  }
}
