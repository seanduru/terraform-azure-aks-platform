
output "vnet_id" {
  description = "Azure VNet resource ID"
  value       = azurerm_virtual_network.aks_vnet.id
}

output "subnet_id" {
  description = "AKS subnet resource ID"
  value       = azurerm_subnet.aks_subnet.id
}
