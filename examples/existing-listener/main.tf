provider "aws" {
  region = var.region
}

################################################################################
# Rules only
#
# The HTTPS listener is owned by another team (or another module). This example
# only attaches rules to it: a public health check bypass, a machine-to-machine
# API path left unauthenticated, and the human facing paths behind OIDC.
#
# Rule priorities matter: the lowest priority wins, so bypass rules must be
# numbered below the authenticated ones.
################################################################################

module "alb_oidc" {
  source = "../../"

  create_listener = false
  listener_arn    = var.listener_arn

  oidc_issuer        = var.oidc_issuer
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret

  rules = {
    # Unauthenticated: answered by the load balancer itself.
    healthcheck = {
      priority     = 10
      authenticate = false

      conditions = {
        path_pattern = { values = ["/healthz", "/readyz"] }
      }

      action = {
        type = "fixed-response"
        fixed_response = {
          content_type = "text/plain"
          message_body = "ok"
          status_code  = "200"
        }
      }
    }

    # Unauthenticated: service-to-service traffic authenticated by the backend.
    api = {
      priority     = 20
      authenticate = false

      conditions = {
        path_pattern = { values = ["/api/*"] }
        source_ip    = { values = ["10.0.0.0/8"] }
      }

      action = {
        type             = "forward"
        target_group_arn = var.api_target_group_arn
      }
    }

    # Authenticated: the web UI.
    web = {
      priority = 100

      conditions = {
        host_header  = { values = [var.domain_name] }
        path_pattern = { values = ["/*"] }
      }

      action = {
        type             = "forward"
        target_group_arn = var.web_target_group_arn
      }
    }

    # Authenticated with a shorter session and a forced re-login.
    admin = {
      priority = 50

      conditions = {
        host_header  = { values = [var.domain_name] }
        path_pattern = { values = ["/admin/*"] }
      }

      action = {
        type             = "forward"
        target_group_arn = var.web_target_group_arn
      }

      oidc = {
        scope                               = "openid email groups"
        session_timeout                     = 900
        session_cookie_name                 = "AdminSession"
        authentication_request_extra_params = { prompt = "login" }
      }
    }
  }

  tags = {
    Example = "existing-listener"
  }
}
