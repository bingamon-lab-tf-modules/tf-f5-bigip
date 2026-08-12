##################################################
# tf-f5-bigip — outputs
#
# NOTHING HERE MAY BE SECRET. Outputs land in OpenTofu state and in
# `tofu output`. These carry the NAMES of credentials and the SHAPE of the
# declaration, never a password, a registration key, or the declaration itself.
##################################################

output "declaration_summary" {
  description = <<-EOT
    What the rendered declaration contains, with no secrets: classes present, VLAN names and
    tags, self IP addresses, routes, provisioning levels, usernames, partitions, and the HA
    role and device group.

    This is the review surface. `do_json` is redacted (ADR 0006), so a plan shows
    "(sensitive value)" with no diff — a change visible nowhere else is visible here.
  EOT
  value       = local.declaration_summary
}

output "summary" {
  description = "Compact description of what this appliance will be."
  value = {
    hostname     = var.hostname
    licensed     = local.license_present
    provisioning = var.provisioning
    vlans        = sort(keys(var.vlans))
    self_ips     = sort(keys(var.self_ips))
    partitions   = sort(keys(var.partitions))
    ha_role      = try(var.ha.role, "standalone")
  }
}

output "validation_errors" {
  description = "Every configuration error found, aggregated. Empty on a valid configuration; a non-empty list fails the plan via the precondition in main.tf. Exposed so it can be asserted directly in tests."
  value       = local.validation_errors
}

output "base_complete" {
  description = "Ordering handshake (ADR 0004). Wire this into the HA peer module's `peer_base_complete` input so device trust is only asserted once both appliances have finished base onboarding."
  value       = bigip_do.base.id
}

output "ha_complete" {
  description = <<-EOT
    Ordering handshake: wire this from the OWNER into the member's
    `peer_ha_complete`, so the member's trust join runs only after the owner's
    declaration (which sets its config-sync address) has converged. Since the
    single-declaration rework this is the device declaration's id — the name
    survives so consumers' wiring does not change. null for standalone.

    CONSUMER WARNING: expose this as its OWN output in any wrapping module —
    folding it into an aggregate output that the owner also reads from the
    member creates a dependency cycle.
  EOT
  value       = var.ha == null ? null : bigip_do.base.id
}

output "partition_names" {
  description = "Names of the LTM partitions created, for pointing CIS at its partition."
  value       = sort(keys(bigip_partition.this))
}
