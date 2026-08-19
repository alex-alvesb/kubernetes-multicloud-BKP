output "artifact_registry_url" {
  value = "us-central1-docker.pkg.dev/kubernetes-multicloud/${google_artifact_registry_repository.sample_app.repository_id}"
}

output "github_actions_wif_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "github_actions_sa_email" {
  value = google_service_account.github_actions.email
}