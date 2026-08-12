##################################################
# Secrecy of the inputs on this page
#
# Only `license` is marked `sensitive`. `users` and `ha` are NOT, deliberately:
# ADR 0006 requires a non-secret `declaration_summary` output carrying usernames,
# the HA role, the device group name and the config-sync address, and a variable
# marked sensitive taints every value derived from it — including that summary.
#
# The secrets in those variables are still protected, by two mechanisms that do
# not depend on the marking here:
#
#   1. Values reach this module from SOPS-decrypted data in the caller, which
#      carries its own sensitivity marks through to the declaration.
#   2. `do_json` is wrapped in `sensitive()` (main.tf), so the rendered
#      declaration never appears in plan or apply output regardless.
#
# Variable values are not written to state (only resource attributes and outputs
# are), so the exposure this trades away is plan-output only, and (2) closes it.
##################################################

##################################################
# Identity
##################################################

variable "hostname" {
  description = "Fully-qualified hostname for the appliance. Becomes the DO tenant hostname and, on an HA owner, the default device group owner."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.hostname))
    error_message = "hostname must be a lowercase fully-qualified domain name, e.g. 'bigip-01.example.lab'."
  }
}

##################################################
# Licensing
##################################################

variable "license" {
  description = "BYOL registration key. Null leaves licensing alone, for an appliance licensed outside Terraform. Only the `regKey` licence type is supported; BIG-IQ licence pools are out of MVP scope."
  type = object({
    reg_key     = string
    add_on_keys = optional(list(string), [])
    overwrite   = optional(bool, false)
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.license == null ? true : length(trimspace(var.license.reg_key)) > 0
    error_message = "license.reg_key must be a non-empty string."
  }
}

##################################################
# Module provisioning
##################################################

variable "provisioning" {
  description = "BIG-IP modules to provision, keyed by module name, valued by provisioning level. CIS requires `ltm` at `nominal` or better."
  type        = map(string)
  default     = { ltm = "nominal" }

  validation {
    condition = alltrue([
      for m in keys(var.provisioning) :
      contains(
        ["afm", "am", "apm", "asm", "avr", "cgnat", "dos", "fps", "gtm", "ilx", "lc", "ltm", "pem", "sslo", "swg", "urldb"],
        m
      )
    ])
    error_message = "provisioning keys must be BIG-IP module names: afm, am, apm, asm, avr, cgnat, dos, fps, gtm, ilx, lc, ltm, pem, sslo, swg, urldb."
  }

  validation {
    condition = alltrue([
      for l in values(var.provisioning) :
      contains(["dedicated", "nominal", "minimum", "none"], l)
    ])
    error_message = "provisioning levels must be one of: dedicated, nominal, minimum, none."
  }
}

##################################################
# Name resolution and time
#
# NTP is not optional hygiene: device trust fails on clock skew, and the error
# does not mention time.
##################################################

variable "dns" {
  description = "DNS resolver configuration. Null omits the DNS class."
  type = object({
    name_servers = optional(list(string), [])
    search       = optional(list(string), [])
  })
  default = null
}

variable "ntp" {
  description = "NTP servers and the appliance timezone. Null omits the NTP class."
  type = object({
    servers  = optional(list(string), [])
    timezone = optional(string, "UTC")
  })
  default = null
}

##################################################
# Layer 2 / Layer 3
##################################################

variable "vlans" {
  description = "VLANs to create, keyed by VLAN name. The key is the name DO assigns, and is what `self_ips[*].vlan_key` refers to."
  type = map(object({
    tag      = optional(number)
    mtu      = optional(number, 1500)
    cmp_hash = optional(string, "default")
    interfaces = list(object({
      name   = string
      tagged = optional(bool)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.vlans : length(v.interfaces) > 0
    ])
    error_message = "each VLAN must list at least one interface."
  }

  validation {
    condition = alltrue([
      for k, v in var.vlans : v.tag == null ? true : (v.tag >= 1 && v.tag <= 4094)
    ])
    error_message = "VLAN tag must be between 1 and 4094."
  }

  validation {
    condition = alltrue([
      for k, v in var.vlans : contains(["default", "dst-ip", "src-ip"], v.cmp_hash)
    ])
    error_message = "VLAN cmp_hash must be one of: default, dst-ip, src-ip."
  }
}

variable "self_ips" {
  description = "Self IPs, keyed by name. `address` carries a prefix length (e.g. '10.10.10.5/24'); `vlan_key` refers to a key of var.vlans."
  type = map(object({
    address       = string
    vlan_key      = string
    allow_service = optional(list(string), ["default"])
    traffic_group = optional(string, "traffic-group-local-only")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.self_ips : can(cidrnetmask(v.address))
    ])
    error_message = "self_ip address must be an IPv4 address with a prefix length, e.g. '10.10.10.5/24'."
  }

  validation {
    condition = alltrue([
      for k, v in var.self_ips :
      contains(["traffic-group-local-only", "traffic-group-1"], v.traffic_group)
    ])
    error_message = "self_ip traffic_group must be one of: traffic-group-local-only, traffic-group-1."
  }

  validation {
    condition = alltrue([
      for k, v in var.self_ips :
      length(v.allow_service) == 1 && contains(["all", "none", "default"], v.allow_service[0])
      ? true
      : alltrue([for s in v.allow_service : can(regex("^\\w+:\\d+$", s))])
    ])
    error_message = "self_ip allow_service must be exactly one of [\"all\"], [\"none\"], [\"default\"], or a list of 'protocol:port' entries such as [\"tcp:443\", \"udp:53\"]."
  }
}

variable "routes" {
  description = "Static routes, keyed by name. `network` defaults to 'default', which is DO's spelling of the default route."
  type = map(object({
    gw      = string
    network = optional(string, "default")
    mtu     = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.routes : can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", v.gw))
    ])
    error_message = "route gw must be an IPv4 address."
  }

  validation {
    condition = alltrue([
      for k, v in var.routes :
      v.network == "default" || can(cidrnetmask(v.network))
    ])
    error_message = "route network must be 'default' or a CIDR, e.g. '10.20.0.0/16'."
  }
}

##################################################
# Local users
##################################################

variable "users" {
  description = "Local users, keyed by username. `partition_access` maps a partition scope to a role. DO's User class accepts ONLY 'Common' and 'all-partitions' as scopes — a named custom partition is rejected by the DO schema (and would not exist at onboarding time anyway). The CIS service account needs all-partitions admin: CIS drives AS3, which requires Administrator."
  type = map(object({
    password         = string
    shell            = optional(string, "tmsh")
    partition_access = optional(map(string), { "all-partitions" = "admin" })
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.users : contains(["bash", "tmsh", "none"], v.shell)
    ])
    error_message = "user shell must be one of: bash, tmsh, none."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.users : [
        for p, r in v.partition_access : contains(
          [
            "acceleration-policy-editor", "admin", "application-editor", "auditor",
            "certificate-manager", "firewall-manager", "fraud-protection-manager",
            "guest", "irule-manager", "manager", "no-access", "operator",
            "resource-admin", "user-manager", "web-application-security-administrator",
            "web-application-security-editor"
          ],
          r
        )
      ]
    ]))
    error_message = "user partition_access roles must be valid BIG-IP roles, e.g. 'admin', 'manager', 'operator', 'guest', 'no-access'."
  }

  validation {
    condition = alltrue([
      for k, v in var.users : alltrue([
        for p, r in v.partition_access : contains(["Common", "all-partitions"], p)
      ])
    ])
    error_message = "user partition_access keys must be 'Common' or 'all-partitions'. DO's User class rejects named partitions (\"should NOT have additional properties\"), and the partition does not exist at onboarding time anyway."
  }
}

##################################################
# High availability
#
# An HA pair is a relationship, not two independent appliances (ADR 0003): trust
# is established from one side, and only the owner emits the DeviceGroup class.
##################################################

variable "ha" {
  description = "High-availability pairing. Null produces a standalone appliance and no second declaration. See ADR 0003 for why the owner/member asymmetry is explicit rather than inferred."
  type = object({
    role           = optional(string)
    local_username = optional(string, "admin")
    local_password = string
    peer_address   = string
    peer_username  = optional(string, "admin")
    peer_password  = string

    config_sync_ip = string

    device_group_name  = optional(string, "failover-group")
    device_group_type  = optional(string, "sync-failover")
    device_group_owner = optional(string)
    members            = optional(list(string), [])
    auto_sync          = optional(bool, true)
    save_on_auto_sync  = optional(bool, false)
    network_failover   = optional(bool, true)
    full_load_on_sync  = optional(bool, false)

    failover_address = optional(string)
    failover_port    = optional(number, 1026)
  })
  default = null

  validation {
    condition     = var.ha == null ? true : contains(["owner", "member"], coalesce(var.ha.role, "unset"))
    error_message = "ha.role is required when ha is set, and must be exactly \"owner\" or \"member\". Exactly one appliance in a pair is the owner."
  }

  validation {
    condition     = var.ha == null ? true : contains(["sync-failover", "sync-only"], var.ha.device_group_type)
    error_message = "ha.device_group_type must be one of: sync-failover, sync-only."
  }

  validation {
    condition     = var.ha == null ? true : can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.ha.config_sync_ip))
    error_message = "ha.config_sync_ip must be a bare IPv4 address with no prefix length."
  }

  validation {
    condition     = var.ha == null ? true : can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.ha.peer_address))
    error_message = "ha.peer_address must be an IPv4 address."
  }
}

variable "peer_base_complete" {
  description = "Ordering handshake (ADR 0004). The landing zone wires the peer module's `base_complete` output into this input, so device trust is only asserted after both appliances have finished base onboarding. Ignored when var.ha is null."
  type        = string
  default     = null
}

##################################################
# Handover seam
##################################################

variable "partitions" {
  description = "LTM partitions, keyed by partition name. This is the CIS handover seam: DO has no Partition class, and CIS requires its partition to exist before it starts (ADR 0001)."
  type = map(object({
    description     = optional(string)
    route_domain_id = optional(number)
  }))
  default = {}
}

##################################################
# Escape hatch
##################################################

variable "do_declaration_overrides" {
  description = <<-EOT
    Last-resort overrides merged over the rendered base declaration, for DO classes this module
    does not yet render as typed variables.

    Merging is TWO-LEVEL: keys are merged at the declaration root, and at the `Common` tenant
    level. It is sufficient to add or wholly replace a class; it does NOT merge within a class.

    Module-owned classes are refused: License, User, DeviceTrust, DeviceGroup, ConfigSync.
    Anything set here is invisible to variable validation, by construction.
  EOT
  type        = any
  default     = {}
}

##################################################
# Test seam
##################################################

variable "enforce_validation" {
  description = "Fail the plan when validation errors exist. Test seam only — leave true in every real configuration."
  type        = bool
  default     = true
}
