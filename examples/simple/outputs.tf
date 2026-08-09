output "listener_arn" {
  description = "ARN of the HTTPS listener created by the module."
  value       = module.alb_oidc.listener_arn
}

output "oidc_endpoints" {
  description = "OIDC endpoints resolved from the provider discovery document."
  value       = module.alb_oidc.oidc_endpoints
}

output "oidc_redirect_uris" {
  description = "Redirect URIs to whitelist in the identity provider application."
  value       = module.alb_oidc.oidc_redirect_uris
}
