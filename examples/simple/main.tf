provider "aws" {
  region = var.region
}

################################################################################
# ALB OIDC authentication
#
# Creates an HTTPS listener on an existing Application Load Balancer that
# authenticates every request against the identity provider before forwarding it
# to the target group. Only the issuer is supplied: the authorization, token and
# user info endpoints are resolved from the provider discovery document.
################################################################################

module "alb_oidc" {
  source = "../../"

  load_balancer_arn = var.load_balancer_arn
  certificate_arn   = var.certificate_arn

  oidc_issuer        = var.oidc_issuer
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  oidc_scope         = "openid email profile"

  default_action = {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }

  callback_domains = [var.domain_name]

  tags = {
    Example = "simple"
  }
}
