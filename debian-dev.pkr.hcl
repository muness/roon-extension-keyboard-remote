packer {
  required_plugins {
    vmware = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

variable "vm_name" {
  type    = string
  default = "roon-remote-debian"
}

variable "debian_arch" {
  type        = string
  default     = "arm64"
  description = "Debian architecture: arm64 (Apple Silicon) or amd64 (Intel)"
}

locals {
  guest_os = var.debian_arch == "arm64" ? "arm-other-64" : "debian12-64"
  iso_url  = var.debian_arch == "arm64" ? "https://cdimage.debian.org/cdimage/weekly-builds/arm64/iso-cd/debian-testing-arm64-netinst.iso" : "https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso"
}

source "vmware-iso" "debian" {
  vm_name       = var.vm_name
  guest_os_type = local.guest_os
  iso_url       = local.iso_url
  iso_checksum  = "none"

  memory               = 1024
  cpus                 = 2
  disk_size            = 20480
  disk_adapter_type    = "nvme"
  disk_type_id         = "0"
  network_adapter_type = "e1000e"

  ssh_username = "root"
  ssh_password = "root"
  ssh_timeout  = "30m"

  shutdown_command = "shutdown -h now"

  http_directory = "."

  vnc_disable_password   = true
  vnc_bind_address       = "127.0.0.1"
  vnc_port_min           = 5901
  vnc_port_max           = 5910

  boot_key_interval      = "10ms"
  boot_keygroup_interval = "100ms"
  boot_wait              = "5s"

  keep_registered      = true
  skip_export          = true
  skip_compaction      = true
  cleanup_remote_cache = false
  version              = 22

  boot_command = [
    "<wait><wait><wait>",
    "c<wait>",
    "linux /install.a64/vmlinuz ",
    "auto=true ",
    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "hostname=debian-dev ",
    "domain=localdomain ",
    "interface=auto ",
    "vga=788 noprompt quiet --<enter>",
    "initrd /install.a64/initrd.gz<enter>",
    "boot<enter>"
  ]

  vmx_data = {
    "firmware"                     = "efi"
    "ethernet0.networkName"        = "NAT"
    "ehci.present"                 = "TRUE"
    "usb_xhci.present"             = "TRUE"
    "sharedFolder.maxNum"          = "1"
    "sharedFolder0.present"        = "TRUE"
    "sharedFolder0.enabled"        = "TRUE"
    "sharedFolder0.readAccess"     = "TRUE"
    "sharedFolder0.writeAccess"    = "TRUE"
    "sharedFolder0.hostPath"       = "/Users/muness1/src"
    "sharedFolder0.guestName"      = "src"
    "sharedFolder0.expiration"     = "never"
    "isolation.tools.hgfs.disable" = "FALSE"
  }
}

build {
  sources = ["source.vmware-iso.debian"]

  provisioner "shell" {
    inline = [
      "# Wait for system to stabilize",
      "sleep 10",

      "# Update package cache",
      "apt-get update",

      "# Install required packages",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \\",
      "  nodejs npm git \\",
      "  bluez bluetooth \\",
      "  open-vm-tools open-vm-tools-desktop \\",
      "  fuse3",

      "# Enable and start Bluetooth",
      "systemctl enable bluetooth",
      "systemctl start bluetooth",

      "# Ensure SSH is enabled",
      "systemctl enable ssh",

      "# Create mount point for shared folders",
      "mkdir -p /mnt/hgfs",

      "# Try to mount shared folders (may fail during provisioning, that's ok)",
      "vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other || true",

      "# Add to fstab for auto-mount on boot",
      "echo '.host:/ /mnt/hgfs fuse.vmhgfs-fuse defaults,allow_other 0 0' >> /etc/fstab",

      "# Enable VMware time sync",
      "vmware-toolbox-cmd timesync enable || true",

      "echo 'Setup complete! VM ready for development.'"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo '✅ Debian Trixie VM created and provisioned!'",
      "echo ''",
      "echo 'To start the VM:'",
      "echo '  vmrun -T fusion start output-debian/${var.vm_name}.vmx nogui'",
      "echo ''",
      "echo 'To find the VM IP:'",
      "echo '  cat /var/db/vmware/vmnet-dhcpd-vmnet8.leases | grep lease | tail -5'",
      "echo ''",
      "echo 'To enable shared folders:'",
      "echo '  1. Open VMware Fusion > VM Settings > Sharing'",
      "echo '  2. Enable shared folders and add your source directory'",
      "echo '  3. In VM: mkdir -p /mnt/hgfs && vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other'",
      "echo ''",
      "echo 'For VS Code Remote-SSH development:'",
      "echo '  1. Install Remote-SSH extension'",
      "echo '  2. Add to ~/.ssh/config:'",
      "echo '       Host debian-dev'",
      "echo '         HostName <VM_IP>'",
      "echo '         User root'",
      "echo '  3. Connect and open /mnt/hgfs/your-project'",
    ]
  }
}
