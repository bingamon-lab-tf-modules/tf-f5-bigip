##################################################
# tf-f5-bigip — declaration rendering and validation
#
# The entire value of this module is a correctly-rendered DO declaration, so the
# rendering rules matter as much as the output (ADR 0001):
#
#   - the declaration is assembled here, in one place, and `jsonencode`d once;
#   - nothing is interpolated from a source whose iteration order is not
#     deterministic, because `do_json` is an opaque string to OpenTofu and a
#     reordered render is an eternal diff;
#   - class and property names follow the DO schema shipped with the provider
#     (`schemas/doschema.json`), not memory.
##################################################

locals {

  ##################################################
  # Envelope
  ##################################################

  # Highest version in the schema's own enum. Pinned rather than variable: a
  # declaration is rendered against the class shapes below, and those shapes are
  # what this version promises.
  do_schema_version = "1.12.0"

  ##################################################
  # Classes — base declaration
  ##################################################

  license_class = var.license == null ? {} : {
    myLicense = merge(
      {
        class       = "License"
        licenseType = "regKey"
        regKey      = var.license.reg_key
        overwrite   = var.license.overwrite
      },
      length(var.license.add_on_keys) == 0 ? {} : { addOnKeys = var.license.add_on_keys },
    )
  }

  provision_class = length(var.provisioning) == 0 ? {} : {
    myProvisioning = merge({ class = "Provision" }, var.provisioning)
  }

  dns_class = var.dns == null ? {} : {
    myDns = {
      class       = "DNS"
      nameServers = var.dns.name_servers
      search      = var.dns.search
    }
  }

  ntp_class = var.ntp == null ? {} : {
    myNtp = {
      class    = "NTP"
      servers  = var.ntp.servers
      timezone = var.ntp.timezone
    }
  }

  # The map key IS the VLAN name in DO, which is what self_ips[*].vlan_key
  # resolves against.
  vlan_classes = {
    for k, v in var.vlans : k => merge(
      {
        class   = "VLAN"
        mtu     = v.mtu
        cmpHash = v.cmp_hash
        interfaces = [
          for i in v.interfaces : merge(
            { name = i.name },
            i.tagged == null ? {} : { tagged = i.tagged },
          )
        ]
      },
      v.tag == null ? {} : { tag = v.tag },
    )
  }

  # DO's allowService is either one of the preset strings or a list of
  # 'protocol:port'. Those are different types, so they cannot come out of a
  # single conditional expression — hence two comprehensions merged, rather than
  # one with a ternary inside.
  # Every class in a DO tenant shares ONE key namespace, so `vlans.external` and
  # `self_ips.external` would collide and merge() would silently drop one. VLAN
  # and User keys stay bare because they ARE the object's name on the appliance
  # (and `self_ips[*].vlan_key` resolves against the VLAN key); self IPs and
  # routes are referenced by nothing, so they are prefixed and cannot collide.
  self_ip_common = {
    for k, v in var.self_ips : "selfip_${k}" => {
      class        = "SelfIp"
      address      = v.address
      vlan         = v.vlan_key
      trafficGroup = v.traffic_group
    }
  }

  self_ip_is_preset = {
    for k, v in var.self_ips :
    "selfip_${k}" => length(v.allow_service) == 1 && contains(["all", "none", "default"], v.allow_service[0])
  }

  self_ip_preset_classes = {
    for k, v in var.self_ips :
    "selfip_${k}" => merge(local.self_ip_common["selfip_${k}"], { allowService = v.allow_service[0] })
    if local.self_ip_is_preset["selfip_${k}"]
  }

  self_ip_list_classes = {
    for k, v in var.self_ips :
    "selfip_${k}" => merge(local.self_ip_common["selfip_${k}"], { allowService = v.allow_service })
    if !local.self_ip_is_preset["selfip_${k}"]
  }

  self_ip_classes = merge(local.self_ip_preset_classes, local.self_ip_list_classes)

  route_classes = {
    for k, v in var.routes : "route_${k}" => merge(
      {
        class   = "Route"
        gw      = v.gw
        network = v.network
      },
      v.mtu == null ? {} : { mtu = v.mtu },
    )
  }

  user_classes = {
    for k, v in var.users : k => {
      class           = "User"
      userType        = "regular"
      password        = v.password
      shell           = v.shell
      partitionAccess = { for p, r in v.partition_access : p => { role = r } }
    }
  }

  ##################################################
  # Base declaration
  ##################################################

  base_common = merge(
    {
      class    = "Tenant"
      hostname = var.hostname
    },
    local.license_class,
    local.provision_class,
    local.dns_class,
    local.ntp_class,
    local.vlan_classes,
    local.self_ip_classes,
    local.route_classes,
    local.user_classes,
  )

  # Two-level merge: root, then Common. Enough to add or replace a whole class,
  # which is what the hatch exists for; it deliberately does not reach inside one.
  override_root   = { for k, v in var.do_declaration_overrides : k => v if k != "Common" }
  override_common = try(var.do_declaration_overrides.Common, {})

  base_declaration = merge(
    {
      schemaVersion = local.do_schema_version
      class         = "Device"
      async         = true
      label         = "tf-f5-bigip base onboarding for ${var.hostname}"
      Common        = merge(local.base_common, local.override_common)
    },
    local.override_root,
  )

  ##################################################
  # HA declaration
  #
  # Split from the base so trust is asserted only after both appliances are
  # onboarded, and so an HA change does not re-push the licence (ADR 0004).
  ##################################################

  ha_device_trust = var.ha == null ? {} : {
    deviceTrust = {
      class          = "DeviceTrust"
      localUsername  = var.ha.local_username
      localPassword  = var.ha.local_password
      remoteHost     = var.ha.peer_address
      remoteUsername = var.ha.peer_username
      remotePassword = var.ha.peer_password
    }
  }

  ha_config_sync = var.ha == null ? {} : {
    configSync = {
      class        = "ConfigSync"
      configsyncIp = var.ha.config_sync_ip
    }
  }

  ha_failover_unicast = try(var.ha.failover_address, null) == null ? {} : {
    failoverUnicast = {
      class   = "FailoverUnicast"
      address = var.ha.failover_address
      port    = var.ha.failover_port
    }
  }

  # Only the owner emits the device group. Asserting it from both sides would
  # work — DO reconciles — but it hides the asymmetry inside DO's behaviour
  # rather than showing it in config (ADR 0003).
  ha_device_group = try(var.ha.role, null) == "owner" ? {
    failoverGroup = {
      class           = "DeviceGroup"
      type            = var.ha.device_group_type
      owner           = coalesce(var.ha.device_group_owner, var.hostname)
      members         = var.ha.members
      autoSync        = var.ha.auto_sync
      saveOnAutoSync  = var.ha.save_on_auto_sync
      networkFailover = var.ha.network_failover
      fullLoadOnSync  = var.ha.full_load_on_sync
    }
  } : {}

  ha_declaration = var.ha == null ? null : {
    schemaVersion = local.do_schema_version
    class         = "Device"
    async         = true
    label         = "tf-f5-bigip HA (${var.ha.role}) for ${var.hostname}"
    Common = merge(
      { class = "Tenant" },
      local.ha_device_trust,
      local.ha_config_sync,
      local.ha_failover_unicast,
      local.ha_device_group,
    )
  }

  ##################################################
  # Validation
  #
  # Cross-variable rules land here and are reported together through ONE
  # precondition, so a plan names every problem at once instead of making the
  # operator re-plan per typo. Single-variable rules live in validation blocks
  # in variables.tf.
  ##################################################

  self_ip_errors = [
    for k, v in var.self_ips :
    "self_ip '${k}' references vlan_key '${v.vlan_key}', which is not a key of var.vlans (defined: ${length(var.vlans) == 0 ? "none" : join(", ", sort(keys(var.vlans)))})."
    if !contains(keys(var.vlans), v.vlan_key)
  ]

  self_ip_addresses = [for k, v in var.self_ips : split("/", v.address)[0]]

  ha_errors = var.ha == null ? [] : concat(
    contains(local.self_ip_addresses, var.ha.config_sync_ip) ? [] : [
      "ha.config_sync_ip '${var.ha.config_sync_ip}' does not match the address of any self_ip (available: ${length(local.self_ip_addresses) == 0 ? "none" : join(", ", sort(local.self_ip_addresses))}). Config sync runs over a self IP, so it must be one this module creates."
    ],
    var.ha.failover_address == null || contains(local.self_ip_addresses, coalesce(var.ha.failover_address, "")) ? [] : [
      "ha.failover_address '${var.ha.failover_address}' does not match the address of any self_ip (available: ${length(local.self_ip_addresses) == 0 ? "none" : join(", ", sort(local.self_ip_addresses))})."
    ],
  )

  # The hatch may not contradict a typed input. These classes carry credentials,
  # licensing, or the HA relationship — the places where a silent contradiction
  # is most damaging (ADR 0005).
  override_denied_classes = ["License", "User", "DeviceTrust", "DeviceGroup", "ConfigSync"]

  override_errors = [
    for k, v in local.override_common :
    "do_declaration_overrides.Common.${k} sets class '${try(v.class, "")}', which is module-owned and refused. Use the typed variable instead (License -> var.license, User -> var.users, DeviceTrust/DeviceGroup/ConfigSync -> var.ha)."
    if contains(local.override_denied_classes, try(v.class, ""))
  ]

  # VLAN and User keys are rendered bare, because they are the object's name on
  # the appliance. That puts them in the same namespace as the tenant's own
  # properties and this module's fixed class names, where a collision would be
  # silently resolved by merge() rather than reported.
  reserved_tenant_keys = ["class", "hostname", "myLicense", "myProvisioning", "myDns", "myNtp"]

  bare_key_errors = concat(
    [
      for k in setintersection(toset(keys(var.vlans)), toset(keys(var.users))) :
      "'${k}' is used as both a VLAN name and a username. Every class in a DO tenant shares one key namespace, so one would silently overwrite the other."
    ],
    [
      for k in sort(concat(keys(var.vlans), keys(var.users))) :
      "'${k}' is reserved: it collides with a tenant property or a class this module renders (${join(", ", local.reserved_tenant_keys)})."
      if contains(local.reserved_tenant_keys, k)
    ],
  )

  validation_errors = concat(
    local.self_ip_errors,
    local.ha_errors,
    local.override_errors,
    local.bare_key_errors,
  )

  ##################################################
  # Summary
  #
  # NOTHING HERE MAY BE SECRET — it is an output, and outputs land in state and
  # in `tofu output`. It carries the NAMES of credentials, never their values.
  #
  # It exists because `do_json` is redacted (ADR 0006), which leaves a plan with
  # no diff at all. This is the review surface for what an apply will change, so
  # a class missing from here changes unreviewed.
  ##################################################

  # Only whether a licence is asserted, never the key. `var.license` is marked
  # sensitive, so the comparison is unwrapped explicitly — one bit, deliberately.
  license_present = nonsensitive(var.license != null)

  declaration_classes = compact([
    local.license_present ? "License" : "",
    length(var.provisioning) > 0 ? "Provision" : "",
    var.dns != null ? "DNS" : "",
    var.ntp != null ? "NTP" : "",
    length(var.vlans) > 0 ? "VLAN" : "",
    length(var.self_ips) > 0 ? "SelfIp" : "",
    length(var.routes) > 0 ? "Route" : "",
    length(var.users) > 0 ? "User" : "",
    var.ha != null ? "DeviceTrust" : "",
    var.ha != null ? "ConfigSync" : "",
    try(var.ha.role, null) == "owner" ? "DeviceGroup" : "",
    try(var.ha.failover_address, null) != null ? "FailoverUnicast" : "",
  ])

  declaration_summary = {
    hostname       = var.hostname
    schema_version = local.do_schema_version
    classes        = local.declaration_classes
    license        = local.license_present ? "regKey" : "none"
    provisioning   = var.provisioning
    dns_servers    = try(var.dns.name_servers, [])
    ntp_servers    = try(var.ntp.servers, [])
    timezone       = try(var.ntp.timezone, null)

    vlans = {
      for k, v in var.vlans : k => {
        tag        = v.tag
        mtu        = v.mtu
        interfaces = [for i in v.interfaces : i.name]
      }
    }

    self_ips = {
      for k, v in var.self_ips : k => {
        address       = v.address
        vlan          = v.vlan_key
        traffic_group = v.traffic_group
      }
    }

    routes = { for k, v in var.routes : k => { network = v.network, gw = v.gw } }

    users      = sort(keys(var.users))
    partitions = sort(keys(var.partitions))

    ha = var.ha == null ? null : {
      role              = var.ha.role
      device_group_name = var.ha.device_group_name
      device_group_type = var.ha.device_group_type
      config_sync_ip    = var.ha.config_sync_ip
      failover_address  = var.ha.failover_address
      peer_address      = var.ha.peer_address
      members           = var.ha.members
    }

    overridden_keys = sort(concat(keys(local.override_root), [
      for k, v in local.override_common : "Common.${k}"
    ]))
  }
}
