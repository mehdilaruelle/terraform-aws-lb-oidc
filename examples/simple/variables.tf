variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "load_balancer_arn" {
  description = "ARN of an existing Application Load Balancer."
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the target group serving the application."
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate used by the HTTPS listener."
  type        = string
}

variable "domain_name" {
  description = "Domain name served by the load balancer, used to build the redirect URI."
  type        = string
  default     = "app.example.com"
}

variable "oidc_issuer" {
  description = "OIDC issuer, e.g. `https://accounts.google.com` or `https://<tenant>.okta.com`."
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
