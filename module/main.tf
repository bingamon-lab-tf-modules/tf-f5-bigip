##################################################
# tf-f5-bigip
#
# Carries an F5 BIG-IP Virtual Edition from a booted OVA to the point where F5
# Container Ingress Services can take over: licensing, module provisioning,
# DNS/NTP, VLANs, self IPs, routes, local users, HA pairing, and the LTM
# partition CIS is pointed at.
#
# It does NOT deploy the appliance — that is tf-ntnx-vm — and it does NOT create
# virtual servers, pools or nodes. CIS owns those, and two controllers writing
# the same LTM objects would revert each other continuously (ADR 0002).
#
# The mechanism is F5 Declarative Onboarding, rendered from typed variables:
# callers never write JSON (ADR 0001). Two declarations are applied, base then
# HA, so device trust is asserted only after both appliances are onboarded and
# an HA change does not re-push the licence (ADR 0004).
#
# See docs/spec.md and docs/decisions/.
##################################################

##################################################
# Validation anchor
#
# terraform_data takes no input and exists purely to host the precondition. ONE
# aggregate precondition rather than one per category, so a plan reports every
# problem at once instead of making the operator re-plan per typo.
#
# var.enforce_validation is a TEST SEAM and defaults to true; tests set it false
# so they can assert which error was raised, because a failed precondition makes
# every output unreadable.
##################################################

resource "terraform_data" "validation" {

  lifecycle {
    precondition {
      condition     = !var.enforce_validation || length(local.validation_errors) == 0
      error_message = "BIG-IP '${var.hostname}' has ${length(local.validation_errors)} configuration error(s):\n  - ${join("\n  - ", local.validation_errors)}"
    }
  }
}

##################################################
# Base onboarding
#
# do_json is wrapped in sensitive() because the provider does NOT mark it
# sensitive (verified in resource_bigip_do.go: only bigip_password and
# bigip_token_auth carry the flag). Unwrapped, the licence key and every
# password would be printed in full in plan and apply output — in CI, into a
# log. See ADR 0006; state at rest is lz-paas ADR 0032.
#
# NOTE: DO has no delete. `tofu destroy` empties state and leaves the appliance
# configured. That is expected — the recovery path for a BIG-IP is rebuilding
# the VE from the OVA, not un-onboarding it.
##################################################

resource "bigip_do" "base" {
  do_json = sensitive(jsonencode(local.base_declaration))

  depends_on = [terraform_data.validation]
}

##################################################
# HA pairing
#
# Ordering within an appliance is the depends_on below. Ordering ACROSS the pair
# is the peer_gate: the landing zone wires the peer module's base_complete
# output into var.peer_base_complete, which makes this declaration wait for the
# peer's base onboarding to finish (ADR 0004).
#
# A value reference, deliberately not module-level depends_on — lz-paas ADR 0024
# measured that expanding to the cross-product of both modules' resources.
##################################################

resource "terraform_data" "peer_gate" {
  count = var.ha == null ? 0 : 1

  input = {
    # Owner side: waits for the member's BASE (ADR 0004 — trust material must
    # exist before the group is created over it).
    base = var.peer_base_complete
    # Member side: waits for the owner's HA declaration — the join asks the
    # owner to add this device, and TMOS refuses while the owner has no
    # config-sync address, which the owner's HA declaration is what sets.
    ha = var.peer_ha_complete
  }
}

resource "bigip_do" "ha" {
  count = var.ha == null ? 0 : 1

  do_json = sensitive(jsonencode(local.ha_declaration))

  depends_on = [
    bigip_do.base,
    terraform_data.peer_gate,
  ]
}

##################################################
# Handover seam
#
# DO has no Partition class, and CIS requires its partition to exist before it
# starts — so this one class of object is imperative (ADR 0001).
##################################################

resource "bigip_partition" "this" {
  for_each = var.partitions

  name            = each.key
  description     = each.value.description
  route_domain_id = each.value.route_domain_id

  depends_on = [bigip_do.base]
}
