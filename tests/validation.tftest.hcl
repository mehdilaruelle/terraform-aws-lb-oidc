mock_provider "aws" {}
mock_provider "http" {}

variables {
  load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/example/1234567890abcdef"
  certificate_arn   = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"

  oidc_issuer             = "https://idp.example.com"
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

################################################################################
# Input validation
################################################################################

run "rejects_a_non_https_issuer" {
  command = plan

  variables {
    oidc_issuer = "http://idp.example.com"
  }

  expect_failures = [var.oidc_issuer]
}

run "rejects_a_scope_without_openid" {
  command = plan

  variables {
    oidc_scope = "profile email"
  }

  expect_failures = [var.oidc_scope]
}

run "rejects_an_unknown_unauthenticated_behaviour" {
  command = plan

  variables {
    oidc_on_unauthenticated_request = "challenge"
  }

  expect_failures = [var.oidc_on_unauthenticated_request]
}

run "rejects_a_session_timeout_above_seven_days" {
  command = plan

  variables {
    oidc_session_timeout = 604801
  }

  expect_failures = [var.oidc_session_timeout]
}

run "rejects_more_than_ten_extra_params" {
  command = plan

  variables {
    oidc_authentication_request_extra_params = {
      p1 = "1", p2 = "2", p3 = "3", p4 = "4", p5 = "5", p6 = "6"
      p7 = "7", p8 = "8", p9 = "9", p10 = "10", p11 = "11"
    }
  }

  expect_failures = [var.oidc_authentication_request_extra_params]
}

run "rejects_an_out_of_range_port" {
  command = plan

  variables {
    port = 70000
  }

  expect_failures = [var.port]
}

run "rejects_an_unsupported_protocol" {
  command = plan

  variables {
    protocol = "TCP"
  }

  expect_failures = [var.protocol]
}

run "rejects_a_forward_default_action_without_target" {
  command = plan

  variables {
    default_action = {
      type = "forward"
    }
  }

  expect_failures = [var.default_action]
}

run "rejects_a_redirect_default_action_without_redirect_block" {
  command = plan

  variables {
    default_action = {
      type = "redirect"
    }
  }

  expect_failures = [var.default_action]
}

################################################################################
# Rule validation
################################################################################

run "rejects_a_rule_without_condition" {
  command = plan

  variables {
    rules = {
      app = {
        priority   = 100
        conditions = {}
        action = {
          type             = "forward"
          target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/app/1111111111111111"
        }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_duplicate_rule_priorities" {
  command = plan

  variables {
    rules = {
      first = {
        priority   = 100
        conditions = { path_pattern = { values = ["/a/*"] } }
        action = {
          type             = "forward"
          target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/app/1111111111111111"
        }
      }
      second = {
        priority   = 100
        conditions = { path_pattern = { values = ["/b/*"] } }
        action = {
          type             = "forward"
          target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/app/1111111111111111"
        }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_forward_rule_without_target" {
  command = plan

  variables {
    rules = {
      app = {
        priority   = 100
        conditions = { path_pattern = { values = ["/*"] } }
        action     = { type = "forward" }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_an_out_of_range_rule_priority" {
  command = plan

  variables {
    rules = {
      app = {
        priority   = 50001
        conditions = { path_pattern = { values = ["/*"] } }
        action = {
          type             = "forward"
          target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/app/1111111111111111"
        }
      }
    }
  }

  expect_failures = [var.rules]
}

################################################################################
# Preconditions
################################################################################

run "requires_a_load_balancer_arn_when_creating_the_listener" {
  command = plan

  variables {
    load_balancer_arn = null
  }

  expect_failures = [aws_lb_listener.this[0]]
}

run "requires_a_certificate_for_an_https_listener" {
  command = plan

  variables {
    certificate_arn = null
  }

  expect_failures = [aws_lb_listener.this[0]]
}

run "requires_https_when_authenticating_the_default_action" {
  command = plan

  variables {
    protocol        = "HTTP"
    port            = 80
    certificate_arn = null
  }

  expect_failures = [aws_lb_listener.this[0]]
}

run "requires_a_default_action_when_authenticating" {
  command = plan

  variables {
    default_action = null
  }

  expect_failures = [aws_lb_listener.this[0]]
}

run "requires_resolvable_endpoints" {
  command = plan

  variables {
    oidc_endpoint_discovery     = false
    oidc_authorization_endpoint = null
    oidc_token_endpoint         = null
    oidc_user_info_endpoint     = null
  }

  expect_failures = [aws_lb_listener.this[0]]
}

run "requires_a_listener_arn_when_not_creating_the_listener" {
  command = plan

  variables {
    create_listener = false
    listener_arn    = null

    rules = {
      app = {
        priority   = 100
        conditions = { path_pattern = { values = ["/*"] } }
        action = {
          type             = "forward"
          target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/app/1111111111111111"
        }
      }
    }
  }

  expect_failures = [aws_lb_listener_rule.this["app"]]
}

run "rejects_a_listener_arn_while_creating_the_listener" {
  command = plan

  variables {
    create_listener = true
    listener_arn    = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/example/1234567890abcdef/abcdef1234567890"
  }

  expect_failures = [aws_lb_listener.this[0]]
}
