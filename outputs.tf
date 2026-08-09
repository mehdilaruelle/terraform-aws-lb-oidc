################################################################################
# Listener
################################################################################

output "listener_arn" {
  description = "ARN of the listener carrying the OIDC configuration (created or provided)."
  value       = local.listener_arn
}

output "listener_id" {
  description = "ID of the listener created by this module."
  value       = try(aws_lb_listener.this[0].id, null)
}

output "listener_created" {
  description = "Whether the listener is managed by this module."
  value       = local.create_listener
}

################################################################################
# Rules
################################################################################

output "rule_ids" {
  description = "Map of listener rule IDs, keyed by the `rules` input key."
  value       = { for key, rule in aws_lb_listener_rule.this : key => rule.id }
}

output "rule_arns" {
  description = "Map of listener rule ARNs, keyed by the `rules` input key."
  value       = { for key, rule in aws_lb_listener_rule.this : key => rule.arn }
}

output "rule_priorities" {
  description = "Map of the effective priorities assigned to each listener rule."
  value       = { for key, rule in aws_lb_listener_rule.this : key => rule.priority }
}

################################################################################
# OIDC
################################################################################

output "oidc_issuer" {
  description = "Issuer identifier used in the authentication actions."
  value       = local.issuer_base
}

output "oidc_endpoints" {
  description = "Resolved OIDC endpoints used in the authentication actions."
  value = {
    authorization = local.authorization_endpoint
    token         = local.token_endpoint
    user_info     = local.user_info_endpoint
  }
}

output "oidc_discovery_url" {
  description = "OpenID Connect discovery document URL used to resolve the endpoints."
  value       = local.discovery_enabled ? local.discovery_url : null
}

output "oidc_session_cookie_name" {
  description = "Base name of the session cookie set by the load balancer. AWS appends a shard index (`-0`, `-1`, ...) to it."
  value       = var.oidc_session_cookie_name
}

output "oidc_redirect_uris" {
  description = "Redirect (callback) URIs to whitelist at the identity provider, derived from `callback_domains` and the host header conditions of authenticated rules."
  value       = local.redirect_uris
}
