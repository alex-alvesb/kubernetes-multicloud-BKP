resource "azurerm_virtual_network" "main" {
  name                = "vnet-kubernetes-multicloud"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    Project     = "kubernetes-multicloud"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]
}