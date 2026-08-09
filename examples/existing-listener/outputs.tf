output "rule_arns" {
  description = "ARNs of the listener rules created by the module."
  value       = module.alb_oidc.rule_arns
}

output "rule_priorities" {
  description = "Effective priority of each listener rule."
  value       = module.alb_oidc.rule_priorities
}

output "oidc_redirect_uris" {
  description = "Redirect URIs to whitelist in the identity provider application."
  value       = module.alb_oidc.oidc_redirect_uris
}
