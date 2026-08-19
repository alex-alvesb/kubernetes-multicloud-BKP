resource "google_artifact_registry_repository" "sample_app" {
  location      = "us-central1"
  repository_id = "kubernetes-multicloud-sample-app"
  format        = "DOCKER"

  labels = {
    project = "kubernetes-multicloud"
  }
}

resource "google_service_account" "github_actions" {
  account_id   = "github-actions-ci"
  display_name = "GitHub Actions CI"
}

resource "google_project_iam_member" "github_actions_ar_writer" {
  project = "kubernetes-multicloud"
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == 'alex-alvesb/kubernetes-multicloud-BKP' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_actions_wif" {
  service_account_id = google_service_account.github_actions.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/alex-alvesb/kubernetes-multicloud-BKP"
}

data "google_compute_default_service_account" "default" {
}

resource "google_project_iam_member" "gke_nodes_ar_reader" {
  project = "kubernetes-multicloud"
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}