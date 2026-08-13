output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "github_actions_client_id" {
  value = azurerm_user_assigned_identity.github_actions.client_id
}

output "azure_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}