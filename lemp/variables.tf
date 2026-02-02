# variables.tf - Input variables for our Proxmox LXC module

variable "proxmox_host_ip" {
  type        = string
  description = "The IP address of the Proxmox host for the CI provisioner."
}

variable "rootfs_storage" {
  type        = string
  description = "The storage pool for the container's root disk (e.g., local-lvm)."
  default     = "local-lvm"
}

variable "root_password" {
  type        = string
  description = "The root password for the LXC container. Set to null for a random password."
  default     = "a_very_secret_password!"
  sensitive   = true
}

variable "container_id" {
  type        = number
  description = "The ID for the LXC container. If null, Proxmox will assign the next available ID."
  default     = "110"

  validation {
    condition     = var.ip_prefix == null || (var.ip_prefix != null && var.container_id != null)
    error_message = "If you specify an 'ip_prefix', you must also specify a 'container_id'."
  }
}

variable "hostname" {
  type        = string
  description = "The hostname for the new LXC container."
  default     = "lemp-iac"
}

variable "ip_prefix" {
  type        = string
  description = "The IP prefix for a static IP (e.g., '192.168.0'), setting a container_id is required for this. If null, DHCP will be used."
  default     = "192.168.0"
}

variable "cidr_suffix" {
  type        = string
  description = "The CIDR suffix for the network (e.g., '24' for /24)."
  default     = "24"
}

variable "gateway" {
  type        = string
  description = "The network gateway IP address. Required for static IP configuration."
  default     = "192.168.0.1"
}

variable "target_node" {
  type        = string
  description = "The name of the target Proxmox node."
}

variable "ostemplate" {
  type        = string
  description = "The name of the LXC template to use (e.g., 'local:vztmpl/alpine-3.23-default_20260116_amd64.tar.xz')."
  default     = "local:alpine-3.23-default_20260116_amd64.tar.xz"
}

variable "ssh_public_key_path" {
  type        = string
  description = "The path to the public SSH key to install in the container."
  default     = "~/.ssh/id_ed25519.pub"
}
