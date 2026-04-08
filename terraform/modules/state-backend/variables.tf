variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Must be a valid AWS region identifier (e.g. us-east-1)."
  }
}

variable "state_key_prefix" {
  description = "Key prefix used within the bucket to separate state files for different root modules."
  type        = string
  default     = "terraform/state"
}
