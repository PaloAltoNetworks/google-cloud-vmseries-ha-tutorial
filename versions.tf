terraform {
  required_version = "> 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">=4.64, < 5.18"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "5.19.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}


# ----------------------------------------------------------------------------------------------------------------
# Retrieve zones
# ----------------------------------------------------------------------------------------------------------------

data "google_client_config" "main" {}

data "google_compute_zones" "main" {
  project = data.google_client_config.main.project
  region  = var.region
}
