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
  ssh_timeout          = "20m"

  shutdown_command     = "poweroff"

  http_directory       = "."

  vnc_disable_password = true
  vnc_bind_address     = "127.0.0.1"
  vnc_port_min         = 5900
  vnc_port_max         = 5900

  boot_key_interval    = "10ms"
  boot_keygroup_interval = "100ms"

  boot_wait            = "10s"
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
    "umount /mnt<enter><wait>",
    "reboot<enter>",

  ]

  vmx_data = {
    "firmware"                     = "efi"
    "ethernet0.networkName"        = "NAT"
    "ehci.present"                 = "TRUE"
    "usb_xhci.present"             = "TRUE"
    "sharedFolder0.present"        = "TRUE"
    "sharedFolder0.enabled"        = "TRUE"
    "sharedFolder0.readAccess"     = "TRUE"
    "sharedFolder0.writeAccess"    = "TRUE"
    "sharedFolder0.hostPath"       = "."
    "sharedFolder0.guestName"      = "extension"
    "sharedFolder0.expiration"     = "never"
    "isolation.tools.hgfs.disable" = "FALSE"
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

      "# Install required packages (including open-vm-tools for shared folders)",
      "apk add nodejs npm git bluez bluez-deprecated open-vm-tools open-vm-tools-hgfs",

      "# Enable and start services",
      "rc-update add bluetooth",
      "rc-update add sshd",
      "rc-update add open-vm-tools",
      "service open-vm-tools start",

      "# Load FUSE kernel module",
      "modprobe fuse",

      "# Mount shared folder",
      "mkdir -p /mnt/hgfs/extension",
      "vmhgfs-fuse .host:/extension /mnt/hgfs/extension -o allow_other",

      "# Create symlink for convenience",
      "ln -s /mnt/hgfs/extension /root/extension",

      "# Install npm dependencies in shared folder",
      "cd /mnt/hgfs/extension && npm install",

      "echo 'Setup complete! Extension mounted at /mnt/hgfs/extension'"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo '✅ VM created and provisioned!'",
      "echo 'Starting VM...'",
      "vmrun -T fusion start output-alpine/${var.vm_name}.vmx nogui",
      "sleep 10",
      "VM_IP=$(vmrun -T fusion getGuestIPAddress output-alpine/${var.vm_name}.vmx -wait)",
      "echo \"\"",
      "echo \"🎉 All done! VM is running at: $VM_IP\"",
      "echo \"\"",
      "echo \"To use the extension:\"",
      "echo \"  1. Connect your Bluetooth remote in VMware Fusion (Virtual Machine > USB & Bluetooth)\"",
      "echo \"  2. SSH into VM: ssh root@$VM_IP (password: root)\"",
      "echo \"  3. Run: cd /root/extension && node keyboard-remote.js\"",
      "echo \"  4. Enable in Roon (Settings > Extensions)\"",
      "echo \"\"",
      "echo \"Your local code is mounted at /root/extension in the VM!\"",
      "echo \"Edit files on your Mac and changes appear in the VM instantly.\"",
    ]
  }
}
