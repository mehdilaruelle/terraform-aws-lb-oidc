################################################################################
# OpenID Connect discovery
#
# Resolves the authorization / token / user info endpoints from the provider
# metadata document so callers only have to supply the issuer.
################################################################################

data "http" "oidc_discovery" {
  count = local.discovery_enabled ? 1 : 0

  url                = local.discovery_url
  request_timeout_ms = 10000

  request_headers = {
    Accept = "application/json"
  }

  retry {
    attempts = 3
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "OIDC discovery document at ${self.url} returned HTTP ${self.status_code}. Set `oidc_endpoint_discovery = false` and provide the endpoints explicitly."
    }
  }
}

################################################################################
# Listener
################################################################################

resource "aws_lb_listener" "this" {
  count = local.create_listener ? 1 : 0

  load_balancer_arn = var.load_balancer_arn
  port              = var.port
  protocol          = var.protocol
  certificate_arn   = var.protocol == "HTTPS" ? var.certificate_arn : null
  ssl_policy        = var.protocol == "HTTPS" ? var.ssl_policy : null

  # Authenticate first, then hand the request over to the target action.
  dynamic "default_action" {
    for_each = var.authenticate_default_action ? [1] : []

    content {
      type  = "authenticate-oidc"
      order = 1

      authenticate_oidc {
        issuer                 = local.issuer_base
        authorization_endpoint = local.authorization_endpoint
        token_endpoint         = local.token_endpoint
        user_info_endpoint     = local.user_info_endpoint
        client_id              = var.oidc_client_id
        client_secret          = var.oidc_client_secret

        scope                               = var.oidc_scope
        session_cookie_name                 = var.oidc_session_cookie_name
        session_timeout                     = var.oidc_session_timeout
        on_unauthenticated_request          = var.oidc_on_unauthenticated_request
        authentication_request_extra_params = var.oidc_authentication_request_extra_params
      }
    }
  }

  dynamic "default_action" {
    for_each = var.default_action != null ? [var.default_action] : []

    content {
      type             = default_action.value.type
      order            = var.authenticate_default_action ? 2 : 1
      target_group_arn = default_action.value.forward == null ? default_action.value.target_group_arn : null

      dynamic "forward" {
        for_each = default_action.value.forward != null ? [default_action.value.forward] : []

        content {
          dynamic "target_group" {
            for_each = forward.value.target_groups

            content {
              arn    = target_group.value.arn
              weight = target_group.value.weight
            }
          }

          dynamic "stickiness" {
            for_each = forward.value.stickiness != null ? [forward.value.stickiness] : []

            content {
              enabled  = stickiness.value.enabled
              duration = stickiness.value.duration
            }
          }
        }
      }

      dynamic "redirect" {
        for_each = default_action.value.redirect != null ? [default_action.value.redirect] : []

        content {
          status_code = redirect.value.status_code
          host        = redirect.value.host
          path        = redirect.value.path
          port        = redirect.value.port
          protocol    = redirect.value.protocol
          query       = redirect.value.query
        }
      }

      dynamic "fixed_response" {
        for_each = default_action.value.fixed_response != null ? [default_action.value.fixed_response] : []

        content {
          content_type = fixed_response.value.content_type
          message_body = fixed_response.value.message_body
          status_code  = fixed_response.value.status_code
        }
      }
    }
  }

  tags = merge(var.tags, var.listener_tags)

  lifecycle {
    precondition {
      condition     = var.load_balancer_arn != null
      error_message = "`load_balancer_arn` is required when `create_listener` is `true`."
    }

    precondition {
      condition     = var.protocol != "HTTPS" || var.certificate_arn != null
      error_message = "`certificate_arn` is required for an HTTPS listener."
    }

    precondition {
      condition     = !var.authenticate_default_action || var.protocol == "HTTPS"
      error_message = "ALB OIDC authentication requires an HTTPS listener; set `protocol = \"HTTPS\"` or `authenticate_default_action = false`."
    }

    precondition {
      condition     = !var.authenticate_default_action || var.default_action != null
      error_message = "`default_action` is required: the listener needs an action to run once the user is authenticated."
    }

    precondition {
      condition = !var.authenticate_default_action || alltrue([
        local.authorization_endpoint != null,
        local.token_endpoint != null,
        local.user_info_endpoint != null,
      ])
      error_message = "Could not resolve the OIDC endpoints. Enable `oidc_endpoint_discovery` or set `oidc_authorization_endpoint`, `oidc_token_endpoint` and `oidc_user_info_endpoint`."
    }
  }
}

################################################################################
# Listener rules
################################################################################

resource "aws_lb_listener_rule" "this" {
  for_each = local.create ? var.rules : {}

  listener_arn = local.listener_arn
  priority     = each.value.priority

  dynamic "action" {
    for_each = each.value.authenticate ? [1] : []

    content {
      type  = "authenticate-oidc"
      order = 1

      authenticate_oidc {
        issuer                 = local.issuer_base
        authorization_endpoint = local.authorization_endpoint
        token_endpoint         = local.token_endpoint
        user_info_endpoint     = local.user_info_endpoint
        client_id              = var.oidc_client_id
        client_secret          = var.oidc_client_secret

        scope                      = coalesce(try(each.value.oidc.scope, null), var.oidc_scope)
        session_cookie_name        = coalesce(try(each.value.oidc.session_cookie_name, null), var.oidc_session_cookie_name)
        session_timeout            = coalesce(try(each.value.oidc.session_timeout, null), var.oidc_session_timeout)
        on_unauthenticated_request = coalesce(try(each.value.oidc.on_unauthenticated_request, null), var.oidc_on_unauthenticated_request)

        authentication_request_extra_params = coalesce(
          try(each.value.oidc.authentication_request_extra_params, null),
          var.oidc_authentication_request_extra_params,
        )
      }
    }
  }

  dynamic "action" {
    for_each = [each.value.action]

    content {
      type             = action.value.type
      order            = each.value.authenticate ? 2 : 1
      target_group_arn = action.value.forward == null ? action.value.target_group_arn : null

      dynamic "forward" {
        for_each = action.value.forward != null ? [action.value.forward] : []

        content {
          dynamic "target_group" {
            for_each = forward.value.target_groups

            content {
              arn    = target_group.value.arn
              weight = target_group.value.weight
            }
          }

          dynamic "stickiness" {
            for_each = forward.value.stickiness != null ? [forward.value.stickiness] : []

            content {
              enabled  = stickiness.value.enabled
              duration = stickiness.value.duration
            }
          }
        }
      }

      dynamic "redirect" {
        for_each = action.value.redirect != null ? [action.value.redirect] : []

        content {
          status_code = redirect.value.status_code
          host        = redirect.value.host
          path        = redirect.value.path
          port        = redirect.value.port
          protocol    = redirect.value.protocol
          query       = redirect.value.query
        }
      }

      dynamic "fixed_response" {
        for_each = action.value.fixed_response != null ? [action.value.fixed_response] : []

        content {
          content_type = fixed_response.value.content_type
          message_body = fixed_response.value.message_body
          status_code  = fixed_response.value.status_code
        }
      }
    }
  }

  # Each `condition` block must carry exactly one match type, so every configured
  # match is expanded into its own block.
  dynamic "condition" {
    for_each = each.value.conditions.host_header != null ? [each.value.conditions.host_header] : []

    content {
      host_header {
        values       = condition.value.values
        regex_values = condition.value.regex_values
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.conditions.path_pattern != null ? [each.value.conditions.path_pattern] : []

    content {
      path_pattern {
        values       = condition.value.values
        regex_values = condition.value.regex_values
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.conditions.http_request_method != null ? [each.value.conditions.http_request_method] : []

    content {
      http_request_method {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.conditions.source_ip != null ? [each.value.conditions.source_ip] : []

    content {
      source_ip {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.conditions.http_headers

    content {
      http_header {
        http_header_name = condition.value.name
        values           = condition.value.values
        regex_values     = condition.value.regex_values
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.conditions.query_strings) > 0 ? [each.value.conditions.query_strings] : []

    content {
      dynamic "query_string" {
        for_each = condition.value

        content {
          key   = query_string.value.key
          value = query_string.value.value
        }
      }
    }
  }

  tags = merge(var.tags, each.value.tags)

  lifecycle {
    precondition {
      condition     = local.listener_arn != null
      error_message = "`listener_arn` is required when `create_listener` is `false`."
    }

    precondition {
      condition = !each.value.authenticate || alltrue([
        local.authorization_endpoint != null,
        local.token_endpoint != null,
        local.user_info_endpoint != null,
      ])
      error_message = "Could not resolve the OIDC endpoints. Enable `oidc_endpoint_discovery` or set `oidc_authorization_endpoint`, `oidc_token_endpoint` and `oidc_user_info_endpoint`."
    }
  }
}
