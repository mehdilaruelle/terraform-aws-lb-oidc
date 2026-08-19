mock_provider "aws" {}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code = 200

      # Mock defaults are literal values: Terraform rejects function calls here,
      # so the discovery document is spelled out rather than `jsonencode`d.
      response_body = "{\"issuer\":\"https://idp.example.com\",\"authorization_endpoint\":\"https://idp.example.com/discovered/authorize\",\"token_endpoint\":\"https://idp.example.com/discovered/token\",\"userinfo_endpoint\":\"https://idp.example.com/discovered/userinfo\",\"jwks_uri\":\"https://idp.example.com/discovered/jwks\"}"
    }
  }
}

variables {
  load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/example/1234567890abcdef"
  certificate_arn   = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"

  oidc_issuer        = "https://idp.example.com"
  oidc_client_id     = "example-client-id"
  oidc_client_secret = "example-client-secret"

  default_action = {
    type             = "forward"
    target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/example/1234567890abcdef"
  }
}

run "resolves_endpoints_from_the_discovery_document" {
  command = plan

  assert {
    condition     = length(data.http.oidc_discovery) == 1
    error_message = "Discovery should run when no endpoint is supplied."
  }

  assert {
    condition     = data.http.oidc_discovery[0].url == "https://idp.example.com/.well-known/openid-configuration"
    error_message = "The discovery URL should be derived from the issuer."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].authorization_endpoint == "https://idp.example.com/discovered/authorize"
    error_message = "The authorization endpoint should come from the discovery document."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].token_endpoint == "https://idp.example.com/discovered/token"
    error_message = "The token endpoint should come from the discovery document."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].user_info_endpoint == "https://idp.example.com/discovered/userinfo"
    error_message = "The user info endpoint should come from the discovery document."
  }

  assert {
    condition     = output.oidc_discovery_url == "https://idp.example.com/.well-known/openid-configuration"
    error_message = "The discovery URL should be exposed as an output."
  }
}

run "explicit_endpoints_win_over_discovery" {
  command = plan

  variables {
    oidc_authorization_endpoint = "https://idp.example.com/explicit/authorize"
    oidc_token_endpoint         = "https://idp.example.com/explicit/token"
    oidc_user_info_endpoint     = "https://idp.example.com/explicit/userinfo"
  }

  assert {
    condition     = length(data.http.oidc_discovery) == 0
    error_message = "Discovery should be skipped when every endpoint is provided."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].authorization_endpoint == "https://idp.example.com/explicit/authorize"
    error_message = "Explicit endpoints should take precedence."
  }
}

run "honours_a_custom_discovery_url" {
  command = plan

  variables {
    oidc_discovery_url = "https://idp.example.com/custom/.well-known/openid-configuration"
  }

  assert {
    condition     = data.http.oidc_discovery[0].url == "https://idp.example.com/custom/.well-known/openid-configuration"
    error_message = "A custom discovery URL should be used verbatim."
  }
}

run "falls_back_to_partial_discovery" {
  command = plan

  variables {
    oidc_token_endpoint = "https://idp.example.com/explicit/token"
  }

  assert {
    condition     = length(data.http.oidc_discovery) == 1
    error_message = "Discovery should still run when only some endpoints are provided."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].token_endpoint == "https://idp.example.com/explicit/token"
    error_message = "The explicitly provided endpoint should be kept."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].authorization_endpoint == "https://idp.example.com/discovered/authorize"
    error_message = "The missing endpoints should be discovered."
  }
}
