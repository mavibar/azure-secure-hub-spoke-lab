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