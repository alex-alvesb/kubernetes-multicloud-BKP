resource "azurerm_user_assigned_identity" "github_actions" {
  name                = "id-github-actions"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = {
    Project     = "kubernetes-multicloud"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_federated_identity_credential" "github_actions" {
  name                       = "github-actions-main"
  user_assigned_identity_id  = azurerm_user_assigned_identity.github_actions.id
  audience                   = ["api://AzureADTokenExchange"]
  issuer                     = "https://token.actions.githubusercontent.com"
  subject                    = "repo:alex-alvesb@157150401/kubernetes-multicloud-BKP@1316552753:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  principal_id                     = azurerm_user_assigned_identity.github_actions.principal_id
  role_definition_name             = "AcrPush"
  scope                             = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}