resource "google_compute_network" "main" {
  name                    = "vpc-kubernetes-multicloud"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name          = "snet-gke-nodes"
  ip_cidr_range = "10.2.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.main.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.2.16.0/20"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.32.0/20"
  }
}