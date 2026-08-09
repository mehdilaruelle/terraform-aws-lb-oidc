################################################################################
# General
################################################################################

variable "create" {
  description = "Controls whether resources should be created (affects nearly all resources)."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "A map of tags to add to all resources created by this module."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# Listener
################################################################################

variable "create_listener" {
  description = <<-EOT
    Whether to create the HTTPS listener that carries the OIDC default action.
    Set to `false` to only attach authenticated rules to an existing listener
    (`listener_arn` then becomes required).
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "load_balancer_arn" {
  description = "ARN of the Application Load Balancer on which the listener is created. Required when `create_listener` is `true`."
  type        = string
  default     = null
}

variable "listener_arn" {
  description = "ARN of an existing listener to attach the rules to. Required when `create_listener` is `false`."
  type        = string
  default     = null
}

variable "port" {
  description = "Port on which the load balancer listens. ALB authentication actions require a TLS-terminated listener."
  type        = number
  default     = 443
  nullable    = false

  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "`port` must be between 1 and 65535."
  }
}

variable "protocol" {
  description = "Protocol for connections from clients to the load balancer. Must be `HTTPS` when the default action authenticates users."
  type        = string
  default     = "HTTPS"
  nullable    = false

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.protocol)
    error_message = "`protocol` must be one of: HTTP, HTTPS."
  }
}

variable "certificate_arn" {
  description = "ARN of the default TLS server certificate. Required when `create_listener` is `true` and `protocol` is `HTTPS`."
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "Name of the SSL policy for the listener. Only used when `protocol` is `HTTPS`."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  nullable    = false
}

variable "listener_tags" {
  description = "Additional tags for the listener, merged on top of `tags`."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "authenticate_default_action" {
  description = <<-EOT
    Whether the listener default action authenticates users through the OIDC
    provider before forwarding. When `false`, the listener is created without an
    `authenticate-oidc` default action and only the rules flagged with
    `authenticate = true` are protected.
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "default_action" {
  description = <<-EOT
    Action performed once the user is authenticated, used as the listener default
    action. Exactly one of `target_group_arn`, `forward`, `redirect` or
    `fixed_response` must be configured, consistently with `type`.
  EOT
  type = object({
    type             = optional(string, "forward")
    target_group_arn = optional(string)
    forward = optional(object({
      target_groups = list(object({
        arn    = string
        weight = optional(number)
      }))
      stickiness = optional(object({
        enabled  = optional(bool, true)
        duration = optional(number, 3600)
      }))
    }))
    redirect = optional(object({
      status_code = optional(string, "HTTP_302")
      host        = optional(string)
      path        = optional(string)
      port        = optional(string)
      protocol    = optional(string)
      query       = optional(string)
    }))
    fixed_response = optional(object({
      content_type = optional(string, "text/plain")
      message_body = optional(string)
      status_code  = optional(string, "200")
    }))
  })
  default = null

  validation {
    condition = var.default_action == null || contains(
      ["forward", "redirect", "fixed-response"],
      coalesce(try(var.default_action.type, null), "forward")
    )
    error_message = "`default_action.type` must be one of: forward, redirect, fixed-response."
  }

  validation {
    condition = var.default_action == null || anytrue([
      var.default_action.type != "forward",
      var.default_action.target_group_arn != null,
      var.default_action.forward != null,
    ])
    error_message = "`default_action` of type `forward` requires either `target_group_arn` or `forward`."
  }

  validation {
    condition     = var.default_action == null || var.default_action.type != "redirect" || var.default_action.redirect != null
    error_message = "`default_action` of type `redirect` requires a `redirect` block."
  }

  validation {
    condition     = var.default_action == null || var.default_action.type != "fixed-response" || var.default_action.fixed_response != null
    error_message = "`default_action` of type `fixed-response` requires a `fixed_response` block."
  }
}

################################################################################
# OIDC identity provider
################################################################################

variable "oidc_issuer" {
  description = "OIDC issuer identifier of the identity provider, e.g. `https://accounts.google.com`."
  type        = string

  validation {
    condition     = can(regex("^https://", var.oidc_issuer))
    error_message = "`oidc_issuer` must be an HTTPS URL."
  }
}

variable "oidc_client_id" {
  description = "OAuth 2.0 client identifier registered with the identity provider."
  type        = string

  validation {
    condition     = length(var.oidc_client_id) > 0
    error_message = "`oidc_client_id` must not be empty."
  }
}

variable "oidc_client_secret" {
  description = "OAuth 2.0 client secret. Read it from a secret store rather than hardcoding it."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.oidc_client_secret) > 0
    error_message = "`oidc_client_secret` must not be empty."
  }
}

variable "oidc_endpoint_discovery" {
  description = <<-EOT
    Resolve the authorization, token and user info endpoints from the provider's
    `/.well-known/openid-configuration` document when they are not set explicitly.
    Requires the machine running Terraform to reach the issuer over HTTPS.
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "oidc_discovery_url" {
  description = "Override for the OpenID Connect discovery document URL. Defaults to `<oidc_issuer>/.well-known/openid-configuration`."
  type        = string
  default     = null
}

variable "oidc_authorization_endpoint" {
  description = "Authorization endpoint of the identity provider. Discovered automatically when `oidc_endpoint_discovery` is `true`."
  type        = string
  default     = null
}

variable "oidc_token_endpoint" {
  description = "Token endpoint of the identity provider. Discovered automatically when `oidc_endpoint_discovery` is `true`."
  type        = string
  default     = null
}

variable "oidc_user_info_endpoint" {
  description = "User info endpoint of the identity provider. Discovered automatically when `oidc_endpoint_discovery` is `true`."
  type        = string
  default     = null
}

variable "oidc_scope" {
  description = "Space-separated set of user claims requested from the identity provider."
  type        = string
  default     = "openid"
  nullable    = false

  validation {
    condition     = contains(split(" ", var.oidc_scope), "openid")
    error_message = "`oidc_scope` must include the `openid` scope."
  }
}

variable "oidc_session_cookie_name" {
  description = "Name of the cookie used by the load balancer to maintain session information."
  type        = string
  default     = "AWSELBAuthSessionCookie"
  nullable    = false
}

variable "oidc_session_timeout" {
  description = "Maximum duration of the authentication session, in seconds. Maximum (and default) is 7 days."
  type        = number
  default     = 604800
  nullable    = false

  validation {
    condition     = var.oidc_session_timeout >= 1 && var.oidc_session_timeout <= 604800
    error_message = "`oidc_session_timeout` must be between 1 and 604800 seconds (7 days)."
  }
}

variable "oidc_on_unauthenticated_request" {
  description = "Behavior when the user is not authenticated. One of `authenticate`, `allow` or `deny`."
  type        = string
  default     = "authenticate"
  nullable    = false

  validation {
    condition     = contains(["authenticate", "allow", "deny"], var.oidc_on_unauthenticated_request)
    error_message = "`oidc_on_unauthenticated_request` must be one of: authenticate, allow, deny."
  }
}

variable "oidc_authentication_request_extra_params" {
  description = "Extra query parameters added to the redirect to the authorization endpoint. Maximum of 10 entries."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(var.oidc_authentication_request_extra_params) <= 10
    error_message = "`oidc_authentication_request_extra_params` accepts at most 10 entries."
  }
}

variable "callback_domains" {
  description = <<-EOT
    Extra domain names served by this listener, used to build the
    `oidc_redirect_uris` output that you must whitelist at the identity provider.
    Host header values from authenticated rules are added automatically.
  EOT
  type        = list(string)
  default     = []
  nullable    = false
}

################################################################################
# Listener rules
################################################################################

variable "rules" {
  description = <<-EOT
    Map of listener rules keyed by an arbitrary, stable identifier. Each rule
    combines a set of conditions with an action, optionally preceded by an
    `authenticate-oidc` action. Set `authenticate = false` to create a bypass
    rule (health checks, machine-to-machine APIs, ...).
  EOT
  type = map(object({
    priority     = optional(number)
    authenticate = optional(bool, true)
    tags         = optional(map(string), {})

    conditions = object({
      host_header = optional(object({
        values       = optional(list(string))
        regex_values = optional(list(string))
      }))
      path_pattern = optional(object({
        values       = optional(list(string))
        regex_values = optional(list(string))
      }))
      http_request_method = optional(object({
        values = list(string)
      }))
      source_ip = optional(object({
        values = list(string)
      }))
      http_headers = optional(list(object({
        name         = string
        values       = optional(list(string))
        regex_values = optional(list(string))
      })), [])
      query_strings = optional(list(object({
        key   = optional(string)
        value = string
      })), [])
    })

    action = object({
      type             = optional(string, "forward")
      target_group_arn = optional(string)
      forward = optional(object({
        target_groups = list(object({
          arn    = string
          weight = optional(number)
        }))
        stickiness = optional(object({
          enabled  = optional(bool, true)
          duration = optional(number, 3600)
        }))
      }))
      redirect = optional(object({
        status_code = optional(string, "HTTP_302")
        host        = optional(string)
        path        = optional(string)
        port        = optional(string)
        protocol    = optional(string)
        query       = optional(string)
      }))
      fixed_response = optional(object({
        content_type = optional(string, "text/plain")
        message_body = optional(string)
        status_code  = optional(string, "200")
      }))
    })

    oidc = optional(object({
      scope                               = optional(string)
      session_cookie_name                 = optional(string)
      session_timeout                     = optional(number)
      on_unauthenticated_request          = optional(string)
      authentication_request_extra_params = optional(map(string))
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.rules : contains(["forward", "redirect", "fixed-response"], v.action.type)
    ])
    error_message = "Every `rules[*].action.type` must be one of: forward, redirect, fixed-response."
  }

  validation {
    condition = alltrue([
      for k, v in var.rules :
      v.action.type != "forward" || v.action.target_group_arn != null || v.action.forward != null
    ])
    error_message = "Every `forward` rule requires either `action.target_group_arn` or `action.forward`."
  }

  validation {
    condition = alltrue([
      for k, v in var.rules :
      (v.action.type != "redirect" || v.action.redirect != null) &&
      (v.action.type != "fixed-response" || v.action.fixed_response != null)
    ])
    error_message = "`redirect` rules require an `action.redirect` block and `fixed-response` rules an `action.fixed_response` block."
  }

  validation {
    condition = alltrue([
      for k, v in var.rules : anytrue([
        v.conditions.host_header != null,
        v.conditions.path_pattern != null,
        v.conditions.http_request_method != null,
        v.conditions.source_ip != null,
        length(v.conditions.http_headers) > 0,
        length(v.conditions.query_strings) > 0,
      ])
    ])
    error_message = "Every rule must define at least one condition."
  }

  validation {
    condition = alltrue([
      for k, v in var.rules :
      v.priority == null || (v.priority >= 1 && v.priority <= 50000)
    ])
    error_message = "`rules[*].priority` must be between 1 and 50000."
  }

  validation {
    condition = length([for k, v in var.rules : v.priority if v.priority != null]) == length(
      distinct([for k, v in var.rules : v.priority if v.priority != null])
    )
    error_message = "`rules[*].priority` must be unique across all rules."
  }

  validation {
    condition = alltrue([
      for k, v in var.rules :
      v.oidc == null || v.oidc.on_unauthenticated_request == null ||
      contains(["authenticate", "allow", "deny"], coalesce(try(v.oidc.on_unauthenticated_request, null), "authenticate"))
    ])
    error_message = "`rules[*].oidc.on_unauthenticated_request` must be one of: authenticate, allow, deny."
  }
}
