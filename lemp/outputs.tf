# outputs.tf - Define the output values
output "proxmox_host_ip" {
description = "The IP address of the Proxmox host for the CI provisioner."
  value       = var.proxmox_host_ip
}
output "container_ip" {
  description = "The IP address of the LEMP LXC container."
  value       = split("/", proxmox_lxc.lemp_iac.network[0].ip)[0]
}
output "container_root_password" {
  description = "The root password set for the new LXC container."
  value       = var.root_password
  sensitive   = true
}
