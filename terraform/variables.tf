
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Project naming prefix"
  type        = string
  default     = "aks-platform"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
