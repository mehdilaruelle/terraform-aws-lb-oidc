locals {
  create          = var.create
  create_listener = local.create && var.create_listener

  # ----------------------------------------------------------------------------
  # OIDC endpoint resolution
  # ----------------------------------------------------------------------------

  issuer_base   = trimsuffix(var.oidc_issuer, "/")
  discovery_url = coalesce(var.oidc_discovery_url, "${local.issuer_base}/.well-known/openid-configuration")

  # Only reach out to the IdP when at least one endpoint is missing.
  endpoints_provided = alltrue([
    var.oidc_authorization_endpoint != null,
    var.oidc_token_endpoint != null,
    var.oidc_user_info_endpoint != null,
  ])
  discovery_enabled = local.create && var.oidc_endpoint_discovery && !local.endpoints_provided

  discovery_document = local.discovery_enabled ? jsondecode(data.http.oidc_discovery[0].response_body) : {}

  authorization_endpoint = var.oidc_authorization_endpoint != null ? var.oidc_authorization_endpoint : try(local.discovery_document.authorization_endpoint, null)
  token_endpoint         = var.oidc_token_endpoint != null ? var.oidc_token_endpoint : try(local.discovery_document.token_endpoint, null)
  user_info_endpoint     = var.oidc_user_info_endpoint != null ? var.oidc_user_info_endpoint : try(local.discovery_document.userinfo_endpoint, null)

  # ----------------------------------------------------------------------------
  # Listener
  # ----------------------------------------------------------------------------

  listener_arn = local.create_listener ? try(aws_lb_listener.this[0].arn, null) : var.listener_arn

  # ----------------------------------------------------------------------------
  # Redirect URIs to whitelist at the identity provider
  # ----------------------------------------------------------------------------

  rule_hosts = flatten([
    for key, rule in var.rules : coalesce(try(rule.conditions.host_header.values, null), [])
    if rule.authenticate
  ])

  callback_hosts = distinct([
    for host in concat(var.callback_domains, local.rule_hosts) : host
    if !strcontains(host, "*") && !strcontains(host, "?")
  ])

  redirect_uris = [for host in local.callback_hosts : "https://${host}/oauth2/idpresponse"]
}
