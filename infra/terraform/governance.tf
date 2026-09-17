variable "owner" {
  description = "Non-secret person or team alias responsible for the lab resources."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) >= 1 && length(trimspace(var.owner)) <= 64
    error_message = "Owner must be 1-64 characters."
  }
}
