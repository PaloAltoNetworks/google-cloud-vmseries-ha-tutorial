output "EXTERNAL_LB_SSH" {
  value = "ssh paloalto@${google_compute_address.extlb_inbound_ip.address} -i ${trim(var.public_key_path, ".pub")}"
}

output "EXTERNAL_LB_URL" {
  value = "http://${google_compute_address.extlb_inbound_ip.address}"
}

output "VMSERIES_ACTIVE" {
  description = "Management URL for vmseries01."
  value       = "https://${module.vmseries["vmseries01"].public_ips[1]}"
}

output "VMSERIES_PASSIVE" {
  description = "Management URL for vmseries02."
  value       = "https://${module.vmseries["vmseries02"].public_ips[1]}"
}

output "VMSERIES_SSH" {
  description = "SSH to Active VM-Series firewall"
  value       = "ssh admin@${module.vmseries["vmseries01"].public_ips[1]} -i ${trimsuffix(var.public_key_path, ".pub")}"
}