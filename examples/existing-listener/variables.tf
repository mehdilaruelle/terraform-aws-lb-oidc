variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "listener_arn" {
  description = "ARN of the existing HTTPS listener to attach the rules to."
  type        = string
}

variable "web_target_group_arn" {
  description = "ARN of the target group serving the web UI."
  type        = string
}

variable "api_target_group_arn" {
  description = "ARN of the target group serving the API."
  type        = string
}

variable "domain_name" {
  description = "Domain name served by the load balancer."
  type        = string
  default     = "app.example.com"
}

variable "oidc_issuer" {
  description = "OIDC issuer of the identity provider."
  type        = string
  default     = "https://accounts.google.com"
}

variable "oidc_client_id" {
  description = "OAuth 2.0 client identifier."
  type        = string
}

variable "oidc_client_secret" {
  description = "OAuth 2.0 client secret."
  type        = string
  sensitive   = true
}
