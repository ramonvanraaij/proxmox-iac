# main.tf - Main logic for creating the Proxmox LXC

terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07" # Using the required version
    }
  }
}

# Provider is configured using environment variables
provider "proxmox" {}

# Define the Alpine Linux LXC container
resource "proxmox_lxc" "lemp_iac" {
  target_node  = var.target_node
  hostname     = var.hostname
  ostemplate   = var.ostemplate
  vmid         = var.container_id
  unprivileged = true
  password     = var.root_password
  start        = true
  onboot       = true

  features {
    nesting = true
  }

  rootfs {
    storage = var.rootfs_storage
    size    = "8G"
  }

  cores  = 2
  memory = 2048
  swap   = 512

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = var.ip_prefix != null ? "${var.ip_prefix}.${var.container_id}/${var.cidr_suffix}" : "dhcp"
    gw     = var.gateway
  }

  ssh_public_keys = file(var.ssh_public_key_path)

  # Step 1: Install OpenSSH inside the container using Proxmox's pct exec command.
  provisioner "local-exec" {
    command = <<-EOT
      sleep 15
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ci@${var.proxmox_host_ip} \
      'sudo pct exec ${self.vmid} -- sh -c "apk update && apk upgrade --available && apk add openssh && rc-update add sshd default && service sshd start"'
    EOT
  }

  # Step 2: After SSH is installed, run Ansible from the local machine.
  provisioner "local-exec" {
    # Use the split() function here to provide a clean IP to Ansible
    # ANSIBLE_HOST_KEY_CHECKING=False to bypass the SSH security prompt
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook --inventory ${split("/", self.network[0].ip)[0]}, --user root playbook.yml"
  }
}
