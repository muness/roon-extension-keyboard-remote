packer {
  required_plugins {
    vmware = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

variable "alpine_version" {
  type    = string
  default = "3.19"
}

variable "vm_name" {
  type    = string
  default = "roon-remote-alpine"
}

variable "alpine_arch" {
  type    = string
  default = "aarch64"
  description = "Alpine architecture: aarch64 (Apple Silicon) or x86_64 (Intel)"
}

locals {
  guest_os = var.alpine_arch == "aarch64" ? "arm-other-64" : "other5xlinux-64"
}

source "vmware-iso" "alpine" {
  vm_name              = var.vm_name
  guest_os_type        = local.guest_os
  iso_url              = "https://dl-cdn.alpinelinux.org/alpine/v${var.alpine_version}/releases/${var.alpine_arch}/alpine-virt-${var.alpine_version}.0-${var.alpine_arch}.iso"
  iso_checksum         = "file:https://dl-cdn.alpinelinux.org/alpine/v${var.alpine_version}/releases/${var.alpine_arch}/alpine-virt-${var.alpine_version}.0-${var.alpine_arch}.iso.sha256"

  memory               = 512
  cpus                 = 1
  disk_size            = 8192
  disk_adapter_type    = "nvme"
  disk_type_id         = "0"
  network_adapter_type = "e1000e"

  ssh_username         = "root"
  ssh_password         = "root"
  ssh_timeout          = "2m"

  shutdown_command     = "poweroff"

  http_directory       = "."

  vnc_disable_password = true
  vnc_bind_address     = "127.0.0.1"
  vnc_port_min         = 5901
  vnc_port_max         = 5910

  boot_key_interval    = "10ms"
  boot_keygroup_interval = "100ms"

  boot_wait            = "10s"

  keep_registered      = true
  skip_export          = true
  skip_compaction      = true
  cleanup_remote_cache = false
  version              = 22

  boot_command         = [
    "root<enter><wait5>",
    "ip link set eth0 up<enter><wait>",
    "udhcpc -i eth0<enter><wait5>",
    "wget http://{{ .HTTPIP }}:{{ .HTTPPort }}/answers<enter><wait>",
    "setup-alpine -f answers<enter><wait5>",
    "root<enter><wait>",
    "root<enter><wait12>",
    "<enter><wait12>",
    "y<enter><wait15>",
    "mount /dev/nvme0n1p3 /mnt<enter><wait>",
    "sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /mnt/etc/ssh/sshd_config<enter><wait>",
    "sed -i 's/^AllowTcpForwarding.*/AllowTcpForwarding yes/' /mnt/etc/ssh/sshd_config<enter><wait>",
    "umount /mnt<enter><wait>",
    "reboot<enter>",

  ]

  vmx_data = {
    "firmware"             = "efi"
    "ethernet0.networkName" = "NAT"
    "ehci.present"         = "TRUE"
    "usb_xhci.present"     = "TRUE"
  }
}

build {
  sources = ["source.vmware-iso.alpine"]

  provisioner "shell" {
    inline = [
      "# Enable community repository",
      "echo 'http://dl-cdn.alpinelinux.org/alpine/latest-stable/community' >> /etc/apk/repositories",

      "# Update package cache",
      "apk update",

      "# Install required packages",
      "apk add nodejs npm git bluez bluez-deprecated open-vm-tools open-vm-tools-guestinfo open-vm-tools-deploypkg open-vm-tools-hgfs fuse3",

      "# Load fuse module",
      "modprobe fuse",
      "echo fuse >> /etc/modules",

      "# Enable and start services",
      "rc-update add bluetooth default",
      "rc-update add sshd default",
      "rc-update add open-vm-tools boot",

      "# Disable chronyd since VMware Tools handles time sync",
      "rc-update del chronyd default 2>/dev/null || true",
      "service chronyd stop 2>/dev/null || true",

      "# Enable VMware time sync",
      "vmware-toolbox-cmd timesync enable",

      "echo 'Setup complete! VM ready for development.'"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo '✅ VM created and provisioned!'",
      "echo ''",
      "echo 'To start the VM:'",
      "echo '  vmrun -T fusion start output-alpine/${var.vm_name}.vmx nogui'",
      "echo ''",
      "echo 'To find the VM IP:'",
      "echo '  cat /var/db/vmware/vmnet-dhcpd-vmnet8.leases | grep lease | tail -5'",
      "echo ''",
      "echo 'For VS Code development:'",
      "echo '  1. Install Remote-SSH extension in VS Code'",
      "echo '  2. Add to ~/.ssh/config:'",
      "echo '       Host alpine-dev'",
      "echo '         HostName <VM_IP>'",
      "echo '         User root'",
      "echo '  3. Connect via VS Code Remote-SSH to alpine-dev'",
      "echo '  4. Copy your project files to /root in the VM'",
    ]
  }
}
