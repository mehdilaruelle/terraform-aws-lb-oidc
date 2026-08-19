variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "name" {
  description = "Name prefix used for every resource created by this example."
  type        = string
  default     = "lb-oidc-complete"
}

variable "github_repository" {
  description = "Repository hosting this module, used for tagging only."
  type        = string
  default     = "mehdilaruelle/terraform-aws-lb-oidc"
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate covering `domain_name`."
  type        = string
}

variable "domain_name" {
  description = "Domain name pointed at the load balancer."
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
