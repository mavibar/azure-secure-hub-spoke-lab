variable "location" {
  description = "Azure region used for lab resources."
  type        = string
  default     = "eastus"
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