output "load_balancer_dns_name" {
  description = "DNS name of the load balancer, to point `domain_name` at."
  value       = aws_lb.this.dns_name
}

output "listener_arn" {
  description = "ARN of the authenticated HTTPS listener."
  value       = module.alb_oidc.listener_arn
}

output "rule_arns" {
  description = "ARNs of the listener rules created by the module."
  value       = module.alb_oidc.rule_arns
}

output "oidc_endpoints" {
  description = "OIDC endpoints resolved from the provider discovery document."
  value       = module.alb_oidc.oidc_endpoints
}

output "oidc_redirect_uris" {
  description = "Redirect URIs to whitelist in the identity provider application."
  value       = module.alb_oidc.oidc_redirect_uris
}
