data "azurerm_client_config" "current" {}

resource "azurerm_container_registry" "main" {
  name                = "acrkubmulticloud${substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 8)}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false

  tags = {
    Project     = "kubernetes-multicloud"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                             = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}