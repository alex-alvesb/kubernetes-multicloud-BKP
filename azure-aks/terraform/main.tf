resource "azurerm_resource_group" "main" {
  name     = "rg-kubernetes-multicloud"
  location = "eastus2"

  tags = {
    Project     = "kubernetes-multicloud"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}