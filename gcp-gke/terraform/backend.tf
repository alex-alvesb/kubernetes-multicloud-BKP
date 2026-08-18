terraform {
  backend "s3" {
    bucket       = "kubernetes-multicloud-tfstate-679346886253"
    key          = "gcp-gke/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}