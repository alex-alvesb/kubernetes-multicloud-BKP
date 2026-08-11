resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-kubernetes-multicloud"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "kubernetes-multicloud"
  kubernetes_version  = "1.36.2"

  default_node_pool {
    name           = "system"
    vm_size        = "Standard_D2s_v7"
    node_count     = 2
    vnet_subnet_id = azurerm_subnet.aks.id

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
  }

  api_server_access_profile {
    authorized_ip_ranges = [var.allowed_public_cidr]
  }

  web_app_routing {
    dns_zone_ids = []
  }

  tags = {
    Project     = "kubernetes-multicloud"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}