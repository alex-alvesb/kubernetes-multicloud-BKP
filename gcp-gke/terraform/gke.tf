resource "google_container_cluster" "main" {
  name     = "gke-kubernetes-multicloud"
  location = "us-central1-a"

  network    = google_compute_network.main.id
  subnetwork = google_compute_subnetwork.gke.id

  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    disk_size_gb = 30
    disk_type    = "pd-standard"
  }

  release_channel {
    channel = "REGULAR"
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.allowed_public_cidr
      display_name = "meu-ip"
    }
  }

  deletion_protection = false

  resource_labels = {
    project    = "kubernetes-multicloud"
    environment = "lab"
    managedby  = "terraform"
  }
}

resource "google_container_node_pool" "primary" {
  name     = "primary-pool"
  cluster  = google_container_cluster.main.id
  location = "us-central1-a"

  node_count = 2

  node_config {
    machine_type = "e2-medium"
    spot         = true
    disk_size_gb = 30
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      project = "kubernetes-multicloud"
    }
  }
}