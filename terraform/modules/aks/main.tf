
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name

  sku_tier = "Free"

  default_node_pool {
    name            = "system"
    node_count      = 1
    vm_size         = "Standard_D2s_v4"
    vnet_subnet_id  = var.subnet_id
    os_disk_size_gb = 30
  }

  identity {
    type = "SystemAssigned"
  }
}
