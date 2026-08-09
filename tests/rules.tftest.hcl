mock_provider "aws" {}
mock_provider "http" {}

variables {
  create_listener = false
  listener_arn    = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/example/1234567890abcdef/abcdef1234567890"

  oidc_issuer             = "https://idp.example.com"
  oidc_client_id          = "example-client-id"
  oidc_client_secret      = "example-client-secret"
  oidc_endpoint_discovery = false

  oidc_authorization_endpoint = "https://idp.example.com/authorize"
  oidc_token_endpoint         = "https://idp.example.com/oauth/token"
  oidc_user_info_endpoint     = "https://idp.example.com/userinfo"

  rules = {
    app = {
      priority = 100
      conditions = {
        host_header  = { values = ["app.example.com"] }
        path_pattern = { values = ["/*"] }
      }
      action = {
        type             = "forward"
        target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/app/1111111111111111"
      }
    }

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

    admin = {
      priority = 50
      conditions = {
        path_pattern        = { values = ["/admin/*"] }
        source_ip           = { values = ["10.0.0.0/8"] }
        http_request_method = { values = ["GET", "POST"] }
        http_headers = [
          { name = "X-Tenant", values = ["acme"] },
        ]
        query_strings = [
          { key = "mode", value = "advanced" },
          { value = "beta" },
        ]
      }
      action = {
        type = "forward"
        forward = {
          target_groups = [
            { arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/blue/2222222222222222", weight = 90 },
            { arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/green/3333333333333333", weight = 10 },
          ]
          stickiness = {
            enabled  = true
            duration = 600
          }
        }
      }
      oidc = {
        scope                               = "openid profile groups"
        session_timeout                     = 900
        session_cookie_name                 = "AdminSession"
        authentication_request_extra_params = { prompt = "login" }
      }
    }
  }
}

run "attaches_rules_to_an_existing_listener" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.this) == 0
    error_message = "`create_listener = false` must not create a listener."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 3
    error_message = "One rule should be created per `rules` entry."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].listener_arn == var.listener_arn
    error_message = "Rules should be attached to the provided listener."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].priority == 100
    error_message = "The configured priority should be used."
  }
}

run "authenticated_rules_run_the_oidc_action_first" {
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.this["app"].action) == 2
    error_message = "An authenticated rule should carry two actions."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].action[0].type == "authenticate-oidc"
    error_message = "The authenticate action must come first."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].action[0].order == 1
    error_message = "The authenticate action must have order 1."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].action[1].type == "forward"
    error_message = "The forward action should follow the authenticate action."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].action[1].order == 2
    error_message = "The forward action must have order 2."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].action[0].authenticate_oidc[0].client_id == var.oidc_client_id
    error_message = "The rule should reuse the module level OIDC client."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this["app"].condition) == 2
    error_message = "Host header and path pattern should expand into two condition blocks."
  }
}

run "bypass_rules_skip_authentication" {
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.this["healthcheck"].action) == 1
    error_message = "A rule with `authenticate = false` should only carry its own action."
  }

  assert {
    condition     = aws_lb_listener_rule.this["healthcheck"].action[0].type == "fixed-response"
    error_message = "The bypass rule should return a fixed response."
  }

  assert {
    condition     = aws_lb_listener_rule.this["healthcheck"].action[0].fixed_response[0].status_code == "200"
    error_message = "The bypass rule should answer with HTTP 200."
  }

  assert {
    condition     = aws_lb_listener_rule.this["healthcheck"].priority == 10
    error_message = "The bypass rule should be evaluated before the authenticated rules."
  }
}

run "per_rule_overrides_and_conditions" {
  command = plan

  assert {
    condition     = aws_lb_listener_rule.this["admin"].action[0].authenticate_oidc[0].scope == "openid profile groups"
    error_message = "A per rule scope override should win over the module default."
  }

  assert {
    condition     = aws_lb_listener_rule.this["admin"].action[0].authenticate_oidc[0].session_timeout == 900
    error_message = "A per rule session timeout override should win over the module default."
  }

  assert {
    condition     = aws_lb_listener_rule.this["admin"].action[0].authenticate_oidc[0].session_cookie_name == "AdminSession"
    error_message = "A per rule cookie name override should win over the module default."
  }

  assert {
    condition     = aws_lb_listener_rule.this["admin"].action[0].authenticate_oidc[0].on_unauthenticated_request == "authenticate"
    error_message = "Unset per rule overrides should fall back to the module default."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this["admin"].condition) == 5
    error_message = "Every configured match should expand into its own condition block."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this["admin"].action[1].forward[0].target_group) == 2
    error_message = "Weighted forwarding should keep both target groups."
  }

  assert {
    condition     = aws_lb_listener_rule.this["admin"].action[1].forward[0].stickiness[0].duration == 600
    error_message = "Target group stickiness should be configurable."
  }
}

run "tags_are_merged" {
  command = plan

  variables {
    tags = { Environment = "test" }
    rules = {
      app = {
        priority = 100
        tags     = { Owner = "platform" }
        conditions = {
          path_pattern = { values = ["/*"] }
        }
        action = {
          type             = "forward"
          target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/app/1111111111111111"
        }
      }
    }
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].tags["Environment"] == "test"
    error_message = "Module level tags should reach the rules."
  }

  assert {
    condition     = aws_lb_listener_rule.this["app"].tags["Owner"] == "platform"
    error_message = "Rule level tags should be merged in."
  }
}
