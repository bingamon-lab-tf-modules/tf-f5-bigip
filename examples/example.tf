##################################################
# tf-f5-bigip — an HA pair
#
# The provider is configured here and passed in; the module declares no provider
# block of its own (the house pattern). One configured provider addresses one
# appliance, so an HA pair is two module instances with two aliased providers.
#
# The management addresses are declared, not discovered: a provider
# configuration cannot take a value that is unknown at plan time. See
# lz-paas ADR 0033.
##################################################

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    bigip = {
      source  = "F5Networks/bigip"
      version = ">= 1.28.0"
    }
  }
}

provider "bigip" {
  alias    = "node_a"
  address  = "192.0.2.10"
  username = var.bigip_username
  password = var.bigip_password
}

provider "bigip" {
  alias    = "node_b"
  address  = "192.0.2.11"
  username = var.bigip_username
  password = var.bigip_password
}

##################################################
# Node A — the device group owner
##################################################

module "bigip_a" {
  source = "github.com/bingamon-lab-tf-modules/tf-f5-bigip//module?ref=v0.1.0"

  providers = {
    bigip = bigip.node_a
  }

  hostname = "bigip-01.example.lab"

  license = {
    reg_key = var.reg_key
  }

  provisioning = {
    ltm = "nominal"
  }

  dns = {
    name_servers = ["192.0.2.53"]
    search       = ["example.lab"]
  }

  # NTP is not optional: device trust fails on clock skew.
  ntp = {
    servers  = ["192.0.2.123"]
    timezone = "UTC"
  }

  vlans = {
    external = {
      tag        = 100
      interfaces = [{ name = "1.1", tagged = true }]
    }
    internal = {
      tag        = 200
      interfaces = [{ name = "1.2", tagged = true }]
    }
    ha = {
      tag        = 300
      interfaces = [{ name = "1.3", tagged = true }]
    }
  }

  self_ips = {
    external = {
      address       = "192.0.2.20/24"
      vlan_key      = "external"
      allow_service = ["none"]
    }
    internal = {
      address       = "198.51.100.20/24"
      vlan_key      = "internal"
      allow_service = ["tcp:443"]
    }
    ha = {
      address       = "203.0.113.20/24"
      vlan_key      = "ha"
      allow_service = ["default"]
    }
  }

  routes = {
    default = {
      gw = "192.0.2.1"
    }
  }

  # The CIS service account. DO is the only way to create it — the provider has
  # no user resource.
  users = {
    cis = {
      password         = var.cis_password
      shell            = "none"
      partition_access = { "all-partitions" = "admin" } # DO accepts only Common / all-partitions
    }
  }

  # The handover seam. CIS requires its partition to already exist.
  partitions = {
    kubernetes = {
      description = "CIS-managed partition"
    }
  }

  ha = {
    role           = "owner"
    local_password = var.bigip_password
    peer_address   = "192.0.2.11"
    peer_password  = var.bigip_password
    config_sync_ip = "203.0.113.20"
    members        = ["bigip-01.example.lab", "bigip-02.example.lab"]
  }

  # Trust is only asserted once node B has finished base onboarding (ADR 0004).
  peer_base_complete = module.bigip_b.base_complete
}

##################################################
# Node B — a device group member
##################################################

module "bigip_b" {
  source = "github.com/bingamon-lab-tf-modules/tf-f5-bigip//module?ref=v0.1.0"

  providers = {
    bigip = bigip.node_b
  }

  hostname = "bigip-02.example.lab"

  license = {
    reg_key = var.reg_key_b
  }

  provisioning = { ltm = "nominal" }

  dns = {
    name_servers = ["192.0.2.53"]
    search       = ["example.lab"]
  }

  ntp = {
    servers  = ["192.0.2.123"]
    timezone = "UTC"
  }

  vlans = {
    external = {
      tag        = 100
      interfaces = [{ name = "1.1", tagged = true }]
    }
    internal = {
      tag        = 200
      interfaces = [{ name = "1.2", tagged = true }]
    }
    ha = {
      tag        = 300
      interfaces = [{ name = "1.3", tagged = true }]
    }
  }

  self_ips = {
    external = {
      address       = "192.0.2.21/24"
      vlan_key      = "external"
      allow_service = ["none"]
    }
    internal = {
      address       = "198.51.100.21/24"
      vlan_key      = "internal"
      allow_service = ["tcp:443"]
    }
    ha = {
      address       = "203.0.113.21/24"
      vlan_key      = "ha"
      allow_service = ["default"]
    }
  }

  routes = {
    default = {
      gw = "192.0.2.1"
    }
  }

  users = {
    cis = {
      password         = var.cis_password
      shell            = "none"
      partition_access = { "all-partitions" = "admin" } # DO accepts only Common / all-partitions
    }
  }

  partitions = {
    kubernetes = {
      description = "CIS-managed partition"
    }
  }

  # A member establishes trust but does not own the device group.
  ha = {
    role           = "member"
    local_password = var.bigip_password
    peer_address   = "192.0.2.10"
    peer_password  = var.bigip_password
    config_sync_ip = "203.0.113.21"
  }
}

##################################################
# Credentials arrive from SOPS in the landing zone; here they are plain
# variables so the example stands alone.
##################################################

variable "bigip_username" {
  type    = string
  default = "admin"
}

variable "bigip_password" {
  type      = string
  sensitive = true
}

variable "cis_password" {
  type      = string
  sensitive = true
}

variable "reg_key" {
  type      = string
  sensitive = true
}

variable "reg_key_b" {
  type      = string
  sensitive = true
}

##################################################
# The review surface. do_json is redacted in a plan, so this is where a change
# to the declaration is actually visible.
##################################################

output "node_a_declaration_summary" {
  value = module.bigip_a.declaration_summary
}

output "node_b_declaration_summary" {
  value = module.bigip_b.declaration_summary
}
