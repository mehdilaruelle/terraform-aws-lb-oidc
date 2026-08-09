mock_provider "aws" {}
mock_provider "http" {}

variables {
  load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/example/1234567890abcdef"
  certificate_arn   = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"

  oidc_issuer             = "https://idp.example.com/"
  oidc_client_id          = "example-client-id"
  oidc_client_secret      = "example-client-secret"
  oidc_endpoint_discovery = false

  oidc_authorization_endpoint = "https://idp.example.com/authorize"
  oidc_token_endpoint         = "https://idp.example.com/oauth/token"
  oidc_user_info_endpoint     = "https://idp.example.com/userinfo"

  default_action = {
    type             = "forward"
    target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/example/1234567890abcdef"
  }
}

run "creates_an_authenticated_https_listener" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.this) == 1
    error_message = "The module should create exactly one listener by default."
  }

  assert {
    condition     = aws_lb_listener.this[0].protocol == "HTTPS"
    error_message = "OIDC authentication requires an HTTPS listener."
  }

  assert {
    condition     = aws_lb_listener.this[0].port == 443
    error_message = "The listener should default to port 443."
  }

  assert {
    condition     = aws_lb_listener.this[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "The listener should default to a TLS 1.3 capable security policy."
  }

  assert {
    condition     = length(aws_lb_listener.this[0].default_action) == 2
    error_message = "The listener should hold an authenticate action followed by the target action."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].type == "authenticate-oidc"
    error_message = "The authenticate action must come first."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].order == 1
    error_message = "The authenticate action must have order 1."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[1].type == "forward"
    error_message = "The second default action should forward to the target group."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[1].order == 2
    error_message = "The forward action must run after the authenticate action."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[1].target_group_arn == var.default_action.target_group_arn
    error_message = "The forward action should target the configured target group."
  }
}

run "propagates_the_oidc_configuration" {
  command = plan

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].issuer == "https://idp.example.com"
    error_message = "A trailing slash on the issuer should be trimmed."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].authorization_endpoint == var.oidc_authorization_endpoint
    error_message = "The authorization endpoint should be passed through."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].token_endpoint == var.oidc_token_endpoint
    error_message = "The token endpoint should be passed through."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].user_info_endpoint == var.oidc_user_info_endpoint
    error_message = "The user info endpoint should be passed through."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].client_id == var.oidc_client_id
    error_message = "The client id should be passed through."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].scope == "openid"
    error_message = "The scope should default to `openid`."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].session_timeout == 604800
    error_message = "The session timeout should default to seven days."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].on_unauthenticated_request == "authenticate"
    error_message = "Unauthenticated requests should be sent to the IdP by default."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].session_cookie_name == "AWSELBAuthSessionCookie"
    error_message = "The session cookie name should default to the AWS one."
  }

  assert {
    condition     = length(data.http.oidc_discovery) == 0
    error_message = "Discovery must not run when every endpoint is provided explicitly."
  }
}

run "supports_custom_oidc_settings" {
  command = plan

  variables {
    oidc_scope                               = "openid profile email groups"
    oidc_session_timeout                     = 3600
    oidc_session_cookie_name                 = "MyAppSession"
    oidc_on_unauthenticated_request          = "deny"
    oidc_authentication_request_extra_params = { prompt = "consent" }
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].scope == "openid profile email groups"
    error_message = "A custom scope should be honoured."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].session_timeout == 3600
    error_message = "A custom session timeout should be honoured."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].session_cookie_name == "MyAppSession"
    error_message = "A custom session cookie name should be honoured."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].on_unauthenticated_request == "deny"
    error_message = "A custom unauthenticated behaviour should be honoured."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].authenticate_oidc[0].authentication_request_extra_params["prompt"] == "consent"
    error_message = "Extra authentication request parameters should be forwarded."
  }
}

run "can_skip_authentication_on_the_default_action" {
  command = plan

  variables {
    authenticate_default_action = false
  }

  assert {
    condition     = length(aws_lb_listener.this[0].default_action) == 1
    error_message = "Without default action authentication only the target action should remain."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].type == "forward"
    error_message = "The remaining default action should be the forward action."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].order == 1
    error_message = "The lone default action should have order 1."
  }
}

run "creates_nothing_when_disabled" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(aws_lb_listener.this) == 0
    error_message = "`create = false` must not create a listener."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 0
    error_message = "`create = false` must not create rules."
  }

  assert {
    condition     = length(data.http.oidc_discovery) == 0
    error_message = "`create = false` must not query the identity provider."
  }
}

run "exposes_redirect_uris" {
  command = plan

  variables {
    callback_domains = ["app.example.com", "*.example.org"]
  }

  assert {
    condition     = output.oidc_redirect_uris == ["https://app.example.com/oauth2/idpresponse"]
    error_message = "Redirect URIs should be built from the callback domains, wildcards excluded."
  }

  assert {
    condition     = output.oidc_session_cookie_name == "AWSELBAuthSessionCookie"
    error_message = "The session cookie name should be exposed."
  }
}
