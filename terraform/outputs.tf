output "host_public_ip" {
  description = "Public IP address of the nested-virtualisation host VM."
  value       = azurerm_public_ip.host.ip_address
}

output "host_private_ip" {
  description = "Private IP address of the host VM within the Azure VNet."
  value       = azurerm_network_interface.host.private_ip_address
}

output "ssh_command" {
  description = "Convenience SSH one-liner to reach the host VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.host.ip_address}"
}

output "resource_group_name" {
  description = "Resource Group containing all lab resources."
  value       = azurerm_resource_group.pxe_lab.name
}
