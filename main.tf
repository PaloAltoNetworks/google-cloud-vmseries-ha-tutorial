

# ----------------------------------------------------------------------------------------------------------------
# Create VPC networks for the environment
# ----------------------------------------------------------------------------------------------------------------

module "vpc_mgmt" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 9.0"
  project_id   = var.project_id
  network_name = "${local.prefix}mgmt-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-mgmt"
      subnet_ip     = var.cidr_mgmt
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name        = "${local.prefix}vmseries-mgmt"
      direction   = "INGRESS"
      priority    = "100"
      description = "Allow ingress access to VM-Series management interface"
      ranges      = var.mgmt_allow_ips
      allow = [
        {
          protocol = "tcp"
          ports    = ["22", "443"]
        }
      ]
    },
    {
      name        = "${local.prefix}vmseries-ha1"
      direction   = "INGRESS"
      priority    = "100"
      description = "Allow ingress access to VM-Series management interface"
      ranges      = [var.cidr_mgmt]
      allow = [
        {
          protocol = "TCP"
          ports    = []
        },
        {
          protocol = "icmp"
          ports    = []
        }
      ]
    }
  ]
}

module "vpc_untrust" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 9.0"
  project_id   = var.project_id
  network_name = "${local.prefix}untrust-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-untrust"
      subnet_ip     = var.cidr_untrust
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}allow-all-untrust"
      direction = "INGRESS"
      priority  = "100"
      ranges    = ["0.0.0.0/0"]
      allow = [
        {
          protocol = "all"
          ports    = []
        }
      ]
    }
  ]
}

module "vpc_trust" {
  source                                 = "terraform-google-modules/network/google"
  version                                = "~> 9.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}trust-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-trust"
      subnet_ip     = var.cidr_trust
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}allow-all-trust"
      direction = "INGRESS"
      priority  = "100"
      ranges    = ["0.0.0.0/0"]
      allow = [
        {
          protocol = "all"
          ports    = []
        }
      ]
    }
  ]
}

module "vpc_ha2" {
  source                                 = "terraform-google-modules/network/google"
  version                                = "~> 9.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}ha2-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-ha2"
      subnet_ip     = var.cidr_ha2
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}allow-all-ha2"
      direction = "INGRESS"
      priority  = "100"
      ranges    = [var.cidr_ha2]
      allow = [
        {
          protocol = "all"
          ports    = []
        }
      ]
    }
  ]
}

resource "google_compute_route" "default_to_vmseries" {
  name         =  "${local.prefix}default-to-vmseries-intlb"
  dest_range   = "0.0.0.0/0"
  network      = module.vpc_trust.network_id
  next_hop_ilb = google_compute_forwarding_rule.intlb.id
  priority     = 100
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
      image = "debian-cloud/debian-11"
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