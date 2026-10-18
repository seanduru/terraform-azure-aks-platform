resource "azurerm_resource_group" "aks_rg" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
}

module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = var.location

  vnet_name   = "vnet-${var.project_name}-${var.environment}"
  subnet_name = "snet-aks-${var.environment}"

  vnet_address_space      = ["10.20.0.0/16"]
  subnet_address_prefixes = ["10.20.1.0/24"]
}

module "aks" {
  source = "./modules/aks"

  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = var.location
  cluster_name        = "aks-${var.project_name}-${var.environment}"

  subnet_id = module.networking.subnet_id
}

module "acr" {
  source = "./modules/acr"

  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = var.location
  acr_name            = "acraksplatformdev12345"
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = module.acr.acr_id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}
