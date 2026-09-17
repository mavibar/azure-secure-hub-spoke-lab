variable "subscription_id" {
  description = "Azure subscription ID where lab resources will be deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Existing Azure resource group provided by the sandbox."
  type        = string
}

variable "project_name" {
  description = "Short name for the project."
  type        = string
  default     = "secureapp"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}
variable "tenant_id" {
  description = "Tenant ID discovered after signing in to the current sandbox."
  type        = string
}

variable "network_cidrs" {
  description = "Persistent lab address plan. Defaults preserve Days 2 and 3."
  type = object({
    hub        = string
    spoke      = string
    management = string
    firewall   = string
    gateway    = string
    web        = string
    app        = string
    data       = string
  })
  default = {
    hub        = "10.10.0.0/16"
    spoke      = "10.20.0.0/16"
    management = "10.10.1.0/24"
    firewall   = "10.10.2.0/26"
    gateway    = "10.10.3.0/27"
    web        = "10.20.1.0/24"
    app        = "10.20.2.0/24"
    data       = "10.20.3.0/24"
  }
  validation {
    condition     = alltrue([for cidr in values(var.network_cidrs) : can(cidrnetmask(cidr))])
    error_message = "Every address must be a valid IPv4 CIDR. Also review subnet containment and overlap."
  }
}

variable "service_ports" {
  description = "TCP destination ports; retain the policy implemented on Day 3."
  type = object({
    web  = number
    app  = number
    data = number
  })
  default = {
    web  = 443
    app  = 443
    data = 1433
  }
  validation {
    condition     = alltrue([for port in values(var.service_ports) : port >= 1 && port <= 65535 && floor(port) == port])
    error_message = "Each TCP port must be an integer from 1 through 65535."
  }
}
