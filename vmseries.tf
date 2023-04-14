# ----------------------------------------------------------------------------------------------------------------
# Local variables
# ----------------------------------------------------------------------------------------------------------------

locals {
  prefix = var.prefix != null && var.prefix != "" ? "${var.prefix}-" : ""

  vmseries_vms = {
    vmseries01 = {
      zone                      = data.google_compute_zones.main.names[0]
      management_private_ip     = cidrhost(var.cidr_mgmt, 2)
      managementpeer_private_ip = cidrhost(var.cidr_mgmt, 3)
      untrust_private_ip        = cidrhost(var.cidr_untrust, 2)
      untrust_gateway_ip        = data.google_compute_subnetwork.untrust.gateway_address
      trust_private_ip          = cidrhost(var.cidr_trust, 2)
      trust_gateway_ip          = data.google_compute_subnetwork.trust.gateway_address
      ha2_private_ip            = cidrhost(var.cidr_ha2, 2)
      ha2_subnet_mask           = cidrnetmask(var.cidr_ha2)
      ha2_gateway_ip            = data.google_compute_subnetwork.ha2.gateway_address
      external_lb_ip            = google_compute_address.external_nat_ip.address
      workload_vm               = cidrhost(var.cidr_trust, 5)
    }

    vmseries02 = {
      zone                      = data.google_compute_zones.main.names[1]
      management_private_ip     = cidrhost(var.cidr_mgmt, 3)
      managementpeer_private_ip = cidrhost(var.cidr_mgmt, 2)
      untrust_private_ip        = cidrhost(var.cidr_untrust, 3)
      untrust_gateway_ip        = data.google_compute_subnetwork.untrust.gateway_address
      trust_private_ip          = cidrhost(var.cidr_trust, 3)
      trust_gateway_ip          = data.google_compute_subnetwork.trust.gateway_address
      ha2_private_ip            = cidrhost(var.cidr_ha2, 3)
      ha2_subnet_mask           = cidrnetmask(var.cidr_ha2)
      ha2_gateway_ip            = data.google_compute_subnetwork.ha2.gateway_address
      external_lb_ip            = google_compute_address.external_nat_ip.address
      workload_vm               = cidrhost(var.cidr_trust, 5)
    }
  }
}


# ----------------------------------------------------------------------------------------------------------------
# Create VM-Series bootstrap package. 
# ----------------------------------------------------------------------------------------------------------------

# Retrieve the subnet IDs for each firewall interface to use inside the bootstrap.xml
data "google_compute_subnetwork" "untrust" {
  self_link = module.vpc_untrust.subnets_self_links[0]
  region    = var.region
}

data "google_compute_subnetwork" "trust" {
  self_link = module.vpc_trust.subnets_self_links[0]
  region    = var.region
}

data "google_compute_subnetwork" "ha2" {
  self_link = module.vpc_ha2.subnets_self_links[0]
  region    = var.region
}

# Modify bootstrap.xml to reflect the VPC networks.
data "template_file" "bootstrap_xml" {
  for_each = local.vmseries_vms
  template = file("bootstrap_files/bootstrap.xml.template")

  vars = {
    external_lb_ip            = google_compute_address.external_nat_ip.address
    management_private_ip     = each.value.management_private_ip
    managementpeer_private_ip = each.value.managementpeer_private_ip
    untrust_private_ip        = each.value.untrust_private_ip
    untrust_gateway_ip        = each.value.untrust_gateway_ip
    trust_private_ip          = each.value.trust_private_ip
    trust_gateway_ip          = each.value.trust_gateway_ip
    ha2_private_ip            = each.value.ha2_private_ip
    ha2_subnet_mask           = each.value.ha2_subnet_mask
    ha2_gateway_ip            = each.value.ha2_gateway_ip
    workload_vm               = each.value.workload_vm
  }
}

resource "local_file" "bootstrap_xml" {
  for_each = local.vmseries_vms
  filename = "tmp/bootstrap-${each.key}"
  content  = data.template_file.bootstrap_xml[each.key].rendered
}

module "iam_service_account" {
  source             = "PaloAltoNetworks/vmseries-modules/google//modules/iam_service_account/"
  service_account_id = "${local.prefix}vmseries-sa"
}

# Create storage bucket to bootstrap VM-Series.
module "bootstrap" {
  for_each        = local.vmseries_vms
  source          = "PaloAltoNetworks/vmseries-modules/google//modules/bootstrap/"
  location        = "US"
  name_prefix     = local.prefix
  service_account = module.iam_service_account.email

  files = {
    "bootstrap_files/init-cfg.txt.sample" = "config/init-cfg.txt"
    "tmp/bootstrap-${each.key}"           = "config/bootstrap.xml"
    "bootstrap_files/authcodes"           = "license/authcodes"
  }

  depends_on = [
    local_file.bootstrap_xml
  ]
}


# ----------------------------------------------------------------------------------------------------------------
# Create 2 VM-Series firewalls and bootstrap their configuration.
# ----------------------------------------------------------------------------------------------------------------

module "vmseries" {
  source                = "PaloAltoNetworks/vmseries-modules/google//modules/vmseries/"
  for_each              = local.vmseries_vms
  name                  = "${local.prefix}${each.key}"
  zone                  = each.value.zone
  ssh_keys              = fileexists(var.public_key_path) ? "admin:${file(var.public_key_path)}" : ""
  vmseries_image        = var.vmseries_image_name
  create_instance_group = true

  service_account = module.iam_service_account.email

  metadata = {
    mgmt-interface-swap                  = "enable"
    vmseries-bootstrap-gce-storagebucket = module.bootstrap[each.key].bucket_name
    serial-port-enable                   = true
  }

  network_interfaces = [
    {
      subnetwork = module.vpc_untrust.subnets_self_links[0]
      private_ip = each.value.untrust_private_ip
    },
    {
      subnetwork       = module.vpc_mgmt.subnets_self_links[0]
      create_public_ip = true
      private_ip       = each.value.management_private_ip
    },
    {
      subnetwork = module.vpc_trust.subnets_self_links[0]
      private_ip = each.value.trust_private_ip
    },
    {
      subnetwork = module.vpc_ha2.subnets_self_links[0]
      private_ip = each.value.ha2_private_ip
    },
  ]

  depends_on = [
    module.bootstrap
  ]
}

# ----------------------------------------------------------------------------------------------------------------
# Create health check for load balancers
# ----------------------------------------------------------------------------------------------------------------


resource "google_compute_region_health_check" "vmseries" {
  name                = "${local.prefix}vmseries-extlb-hc"
  project             = var.project_id
  region              = var.region
  check_interval_sec  = 3
  healthy_threshold   = 1
  timeout_sec         = 1
  unhealthy_threshold = 1

  http_health_check {
    port         = 80
    request_path = "/php/login.php"
  }
}


# ----------------------------------------------------------------------------------------------------------------
# Create an internal load balancer to distribute traffic to VM-Series trust interfaces.
# ----------------------------------------------------------------------------------------------------------------

resource "google_compute_forwarding_rule" "intlb" {
  name                  = "${local.prefix}vmseries-intlb-rule1"
  load_balancing_scheme = "INTERNAL"
  ip_address            = cidrhost(var.cidr_trust, 10)
  ip_protocol           = "TCP"
  all_ports             = true
  subnetwork            = module.vpc_trust.subnets_self_links[0]
  allow_global_access   = true
  backend_service       = google_compute_region_backend_service.intlb.self_link
}

resource "google_compute_region_backend_service" "intlb" {
  provider         = google-beta
  name             = "${local.prefix}vmseries-intlb"
  health_checks    = [google_compute_region_health_check.vmseries.self_link] #[google_compute_health_check.intlb.self_link]
  network          = module.vpc_trust.network_id
  session_affinity = null

  dynamic "backend" {
    for_each = { for k, v in module.vmseries : k => v.instance_group_self_link }
    content {
      group    = backend.value
      failover = false
    }
  }

  connection_tracking_policy {
    tracking_mode                                = "PER_SESSION"
    connection_persistence_on_unhealthy_backends = "NEVER_PERSIST"
    idle_timeout_sec                             = 600
  }
}

# ----------------------------------------------------------------------------------------------------------------
# Create an external load balancer to distribute traffic to VM-Series trust interfaces.
# ----------------------------------------------------------------------------------------------------------------

resource "google_compute_address" "external_nat_ip" {
  name         = "${local.prefix}vmseries-extlb-ip"
  address_type = "EXTERNAL"
}

resource "google_compute_forwarding_rule" "rule" {
  name                  = "${local.prefix}vmseries-extlb-rule1"
  project               = var.project_id
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  all_ports             = true
  ip_address            = google_compute_address.external_nat_ip.address
  ip_protocol           = "L3_DEFAULT"
  backend_service       = google_compute_region_backend_service.extlb.self_link
}

resource "google_compute_region_backend_service" "extlb" {
  provider              = google-beta
  name                  = "${local.prefix}vmseries-extlb"
  project               = var.project_id
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.vmseries.self_link]
  protocol              = "UNSPECIFIED"

  dynamic "backend" {
    for_each = [for k, v in module.vmseries : module.vmseries[k].instance_group_self_link]
    content {
      group = backend.value
    }
  }

  connection_tracking_policy {
    tracking_mode                                = "PER_SESSION"
    connection_persistence_on_unhealthy_backends = "NEVER_PERSIST"
  }
}