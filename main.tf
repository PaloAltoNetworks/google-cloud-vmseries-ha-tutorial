terraform {
  required_version = ">= 0.15.3, < 2.0"
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

# ----------------------------------------------------------------------------------------------------------------
# Create a VM for testing purposes. 
# ----------------------------------------------------------------------------------------------------------------

resource "google_compute_instance" "workload_vm" {
  count                     = (var.create_workload_vm ? 1 : 0)
  name                      = "${local.prefix}workload-vm"
  project                   = var.project_id
  machine_type              = "n2-standard-2"
  zone                      = data.google_compute_zones.main.names[0]
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = "paloalto:${file(var.public_key_path)}"
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    subnetwork = module.vpc_trust.subnets_ids[0]
    network_ip = cidrhost(var.cidr_trust, 5)
  }

  metadata_startup_script = <<SCRIPT
    echo "while :" >> /network-check.sh
    echo "do" >> /network-check.sh
    echo "  timeout -k 2 2 ping -c 1  8.8.8.8 >> /dev/null" >> /network-check.sh
    echo "  if [ $? -eq 0 ]; then" >> /network-check.sh
    echo "    echo \$(date) -- Online -- Source IP = \$(curl https://checkip.amazonaws.com -s --connect-timeout 1)" >> /network-check.sh
    echo "  else" >> /network-check.sh
    echo "    echo \$(date) -- Offline" >> /network-check.sh
    echo "  fi" >> /network-check.sh
    echo "  sleep 1" >> /network-check.sh
    echo "done" >> /network-check.sh
    chmod +x /network-check.sh

    while ! ping -q -c 1 -W 1 google.com >/dev/null
    do
      echo "waiting for internet connection..."
      sleep 10s
    done
    echo "internet connection available!"

    apt update && apt install -y apache2

    SCRIPT
}
