provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = var.name

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Name       = local.name
    Example    = "complete"
    Repository = "https://github.com/${var.github_repository}"
  }
}

################################################################################
# Network
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = local.tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = local.tags
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.name}-public-${local.azs[count.index]}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = local.tags
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Load balancer
#
# The load balancer must be able to reach the identity provider over the public
# internet: public subnets with an internet gateway, or private subnets behind a
# NAT gateway.
################################################################################

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Ingress from the internet, egress to the targets and the identity provider"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet, redirected to HTTPS"

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.alb.id
  description       = "Targets and identity provider"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_lb" "this" {
  name               = local.name
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = local.tags
}

resource "aws_lb_target_group" "web" {
  name        = "${local.name}-web"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = "/healthz"
    matcher = "200"
  }

  tags = local.tags
}

resource "aws_lb_target_group" "api" {
  name        = "${local.name}-api"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

# Plain HTTP is redirected to HTTPS: the authentication actions below only make
# sense on a TLS terminated listener.
resource "aws_lb_listener" "redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.tags
}

################################################################################
# ALB OIDC authentication
################################################################################

module "alb_oidc" {
  source = "../../"

  load_balancer_arn = aws_lb.this.arn
  certificate_arn   = var.certificate_arn

  # Only the issuer is needed: the endpoints come from
  # <issuer>/.well-known/openid-configuration.
  oidc_issuer        = var.oidc_issuer
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret

  oidc_scope                      = "openid email profile"
  oidc_session_timeout            = 43200
  oidc_session_cookie_name        = "AWSELBAuthSessionCookie"
  oidc_on_unauthenticated_request = "authenticate"

  # Everything that is not matched by a rule is authenticated, then forwarded.
  default_action = {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  rules = {
    # Load balancer answers directly, no round trip to the identity provider.
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

    # Machine-to-machine calls carry their own bearer token.
    api = {
      priority     = 20
      authenticate = false

      conditions = {
        path_pattern = { values = ["/api/*"] }
        http_headers = [
          { name = "Authorization", values = ["Bearer *"] },
        ]
      }

      action = {
        type             = "forward"
        target_group_arn = aws_lb_target_group.api.arn
      }
    }

    # Sensitive area: short session and forced re-authentication.
    admin = {
      priority = 50

      conditions = {
        host_header  = { values = [var.domain_name] }
        path_pattern = { values = ["/admin/*"] }
        source_ip    = { values = ["10.0.0.0/8"] }
      }

      action = {
        type = "forward"
        forward = {
          target_groups = [
            { arn = aws_lb_target_group.web.arn, weight = 100 },
          ]
          stickiness = {
            enabled  = true
            duration = 3600
          }
        }
      }

      oidc = {
        scope                               = "openid email groups"
        session_timeout                     = 900
        session_cookie_name                 = "AdminSession"
        on_unauthenticated_request          = "deny"
        authentication_request_extra_params = { prompt = "login" }
      }
    }
  }

  callback_domains = [var.domain_name]

  tags = local.tags
}
