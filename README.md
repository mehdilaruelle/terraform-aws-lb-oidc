# AWS Application Load Balancer OIDC authentication — Terraform module

[![CI](https://github.com/your-org/terraform-aws-lb-oidc/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/terraform-aws-lb-oidc/actions/workflows/ci.yml)
[![Terraform Registry](https://img.shields.io/badge/terraform-registry-7B42BC?logo=terraform)](https://registry.terraform.io/modules/your-org/lb-oidc/aws/latest)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Offload OpenID Connect authentication to an Application Load Balancer. The load
balancer runs the whole authorization code flow, keeps the session cookie, and
only then forwards the request to your targets — your application never has to
implement OIDC.

```
              ┌──────────────────────────── not authenticated ────────────────────────────┐
              │                                                                           ▼
Client ──▶ ALB HTTPS listener ──▶ authenticate-oidc action ──▶ forward action ──▶ Target   IdP
                                          ▲                                               │
                                          └──────── /oauth2/idpresponse callback ─────────┘
```

Once authenticated, the targets receive three extra headers:

| Header | Content |
| --- | --- |
| `x-amzn-oidc-accesstoken` | Access token returned by the token endpoint |
| `x-amzn-oidc-identity` | `sub` claim of the user |
| `x-amzn-oidc-data` | Signed JWT holding the user claims |

## Features

- Creates the HTTPS listener with an `authenticate-oidc` default action, or
  attaches authenticated rules to a listener you already own.
- **Endpoint discovery**: supply only the issuer, the authorization, token and
  user info endpoints are read from `/.well-known/openid-configuration`.
- Per-rule routing with every ALB condition type (host, path, method, source IP,
  headers, query strings) and every action type (forward, weighted forward with
  stickiness, redirect, fixed response).
- **Bypass rules** (`authenticate = false`) for health checks and
  machine-to-machine APIs that must not be redirected to the IdP.
- Per-rule OIDC overrides: scope, session timeout, cookie name, behaviour on
  unauthenticated requests, extra authorization parameters.
- Computes the redirect URIs you have to whitelist at the identity provider.
- Input validation and preconditions that fail at plan time rather than in the
  middle of an apply.

Works with any compliant provider: Okta, Auth0, Microsoft Entra ID, Google,
Keycloak, GitLab, Ping, Authentik, Dex…

## Usage

### Protect everything behind the load balancer

```hcl
module "alb_oidc" {
  source  = "your-org/lb-oidc/aws"
  version = "~> 1.0"

  load_balancer_arn = aws_lb.this.arn
  certificate_arn   = aws_acm_certificate.this.arn

  oidc_issuer        = "https://dev-12345.okta.com/oauth2/default"
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret

  default_action = {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  callback_domains = ["app.example.com"]
}
```

`module.alb_oidc.oidc_redirect_uris` gives you the callback URLs to register in
the identity provider application.

### Add authenticated rules to an existing listener

```hcl
module "alb_oidc" {
  source  = "your-org/lb-oidc/aws"
  version = "~> 1.0"

  create_listener = false
  listener_arn    = aws_lb_listener.https.arn

  oidc_issuer        = "https://accounts.google.com"
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret

  rules = {
    # Lower priority wins: the bypass rules must be evaluated first.
    healthcheck = {
      priority     = 10
      authenticate = false

      conditions = {
        path_pattern = { values = ["/healthz"] }
      }

      action = {
        type           = "fixed-response"
        fixed_response = { message_body = "ok", status_code = "200" }
      }
    }

    web = {
      priority = 100

      conditions = {
        host_header  = { values = ["app.example.com"] }
        path_pattern = { values = ["/*"] }
      }

      action = {
        type             = "forward"
        target_group_arn = aws_lb_target_group.web.arn
      }
    }
  }
}
```

### Skip discovery and pin the endpoints

Discovery makes an outbound HTTPS call from wherever Terraform runs. In an
air-gapped pipeline, set the endpoints explicitly instead:

```hcl
  oidc_endpoint_discovery     = false
  oidc_authorization_endpoint = "https://idp.example.com/authorize"
  oidc_token_endpoint         = "https://idp.example.com/oauth/token"
  oidc_user_info_endpoint     = "https://idp.example.com/userinfo"
```

## Before you apply

- **The listener must terminate TLS.** ALB refuses `authenticate-oidc` on a plain
  HTTP listener. Redirect port 80 to 443 separately.
- **Register the callback URL** `https://<your-domain>/oauth2/idpresponse` in the
  identity provider application, for every domain served by the listener.
- **The load balancer needs egress to the IdP** (public subnets with an internet
  gateway, or private subnets behind a NAT gateway) and must resolve its DNS
  name. Authentication fails with an HTTP 500 otherwise.
- **`on_unauthenticated_request` matters for APIs.** `authenticate` sends a 302
  to the IdP, which a non-browser client cannot follow. Use `deny` (HTTP 401) for
  API paths, or a bypass rule.
- **Session cookies are sharded.** The session data is split across
  `AWSELBAuthSessionCookie-0`, `-1`, … Do not strip unknown cookies at the edge,
  and keep the claim set small: a large `scope` can blow past the 4 KB per-cookie
  limit.
- **`session_timeout` maxes out at 7 days** (604800 s), and the refresh token is
  used to renew the session in the background when the IdP returns one.
- **There is no ALB-side logout.** Clearing the session means expiring the
  `AWSELBAuthSessionCookie*` cookies from your application and redirecting to the
  IdP end-session endpoint.
- **Validate `x-amzn-oidc-data` in your backend.** The ALB signs it, but a target
  reachable outside the load balancer can be fed a forged header — restrict the
  target security group to the load balancer and verify the signature against the
  regional public key endpoint.

## Examples

| Example | Description |
| --- | --- |
| [simple](examples/simple) | HTTPS listener with an OIDC default action on an existing ALB |
| [existing-listener](examples/existing-listener) | Authenticated rules and bypass rules on a listener owned elsewhere |
| [complete](examples/complete) | Self-contained VPC, ALB, target groups, HTTP→HTTPS redirect, mixed rules |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.4 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |
| <a name="provider_http"></a> [http](#provider\_http) | >= 3.4 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [http_http.oidc_discovery](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_oidc_client_id"></a> [oidc\_client\_id](#input\_oidc\_client\_id) | OAuth 2.0 client identifier registered with the identity provider. | `string` | n/a | yes |
| <a name="input_oidc_client_secret"></a> [oidc\_client\_secret](#input\_oidc\_client\_secret) | OAuth 2.0 client secret. Read it from a secret store rather than hardcoding it. | `string` | n/a | yes |
| <a name="input_oidc_issuer"></a> [oidc\_issuer](#input\_oidc\_issuer) | OIDC issuer identifier of the identity provider, e.g. `https://accounts.google.com`. | `string` | n/a | yes |
| <a name="input_authenticate_default_action"></a> [authenticate\_default\_action](#input\_authenticate\_default\_action) | Whether the listener default action authenticates users through the OIDC<br/>provider before forwarding. When `false`, the listener is created without an<br/>`authenticate-oidc` default action and only the rules flagged with<br/>`authenticate = true` are protected. | `bool` | `true` | no |
| <a name="input_callback_domains"></a> [callback\_domains](#input\_callback\_domains) | Extra domain names served by this listener, used to build the<br/>`oidc_redirect_uris` output that you must whitelist at the identity provider.<br/>Host header values from authenticated rules are added automatically. | `list(string)` | `[]` | no |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ARN of the default TLS server certificate. Required when `create_listener` is `true` and `protocol` is `HTTPS`. | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created (affects nearly all resources). | `bool` | `true` | no |
| <a name="input_create_listener"></a> [create\_listener](#input\_create\_listener) | Whether to create the HTTPS listener that carries the OIDC default action.<br/>Set to `false` to only attach authenticated rules to an existing listener<br/>(`listener_arn` then becomes required). | `bool` | `true` | no |
| <a name="input_default_action"></a> [default\_action](#input\_default\_action) | Action performed once the user is authenticated, used as the listener default<br/>action. Exactly one of `target_group_arn`, `forward`, `redirect` or<br/>`fixed_response` must be configured, consistently with `type`. | <pre>object({<br/>    type             = optional(string, "forward")<br/>    target_group_arn = optional(string)<br/>    forward = optional(object({<br/>      target_groups = list(object({<br/>        arn    = string<br/>        weight = optional(number)<br/>      }))<br/>      stickiness = optional(object({<br/>        enabled  = optional(bool, true)<br/>        duration = optional(number, 3600)<br/>      }))<br/>    }))<br/>    redirect = optional(object({<br/>      status_code = optional(string, "HTTP_302")<br/>      host        = optional(string)<br/>      path        = optional(string)<br/>      port        = optional(string)<br/>      protocol    = optional(string)<br/>      query       = optional(string)<br/>    }))<br/>    fixed_response = optional(object({<br/>      content_type = optional(string, "text/plain")<br/>      message_body = optional(string)<br/>      status_code  = optional(string, "200")<br/>    }))<br/>  })</pre> | `null` | no |
| <a name="input_listener_arn"></a> [listener\_arn](#input\_listener\_arn) | ARN of an existing listener to attach the rules to. Required when `create_listener` is `false`. | `string` | `null` | no |
| <a name="input_listener_tags"></a> [listener\_tags](#input\_listener\_tags) | Additional tags for the listener, merged on top of `tags`. | `map(string)` | `{}` | no |
| <a name="input_load_balancer_arn"></a> [load\_balancer\_arn](#input\_load\_balancer\_arn) | ARN of the Application Load Balancer on which the listener is created. Required when `create_listener` is `true`. | `string` | `null` | no |
| <a name="input_oidc_authentication_request_extra_params"></a> [oidc\_authentication\_request\_extra\_params](#input\_oidc\_authentication\_request\_extra\_params) | Extra query parameters added to the redirect to the authorization endpoint. Maximum of 10 entries. | `map(string)` | `{}` | no |
| <a name="input_oidc_authorization_endpoint"></a> [oidc\_authorization\_endpoint](#input\_oidc\_authorization\_endpoint) | Authorization endpoint of the identity provider. Discovered automatically when `oidc_endpoint_discovery` is `true`. | `string` | `null` | no |
| <a name="input_oidc_discovery_url"></a> [oidc\_discovery\_url](#input\_oidc\_discovery\_url) | Override for the OpenID Connect discovery document URL. Defaults to `<oidc_issuer>/.well-known/openid-configuration`. | `string` | `null` | no |
| <a name="input_oidc_endpoint_discovery"></a> [oidc\_endpoint\_discovery](#input\_oidc\_endpoint\_discovery) | Resolve the authorization, token and user info endpoints from the provider's<br/>`/.well-known/openid-configuration` document when they are not set explicitly.<br/>Requires the machine running Terraform to reach the issuer over HTTPS. | `bool` | `true` | no |
| <a name="input_oidc_on_unauthenticated_request"></a> [oidc\_on\_unauthenticated\_request](#input\_oidc\_on\_unauthenticated\_request) | Behavior when the user is not authenticated. One of `authenticate`, `allow` or `deny`. | `string` | `"authenticate"` | no |
| <a name="input_oidc_scope"></a> [oidc\_scope](#input\_oidc\_scope) | Space-separated set of user claims requested from the identity provider. | `string` | `"openid"` | no |
| <a name="input_oidc_session_cookie_name"></a> [oidc\_session\_cookie\_name](#input\_oidc\_session\_cookie\_name) | Name of the cookie used by the load balancer to maintain session information. | `string` | `"AWSELBAuthSessionCookie"` | no |
| <a name="input_oidc_session_timeout"></a> [oidc\_session\_timeout](#input\_oidc\_session\_timeout) | Maximum duration of the authentication session, in seconds. Maximum (and default) is 7 days. | `number` | `604800` | no |
| <a name="input_oidc_token_endpoint"></a> [oidc\_token\_endpoint](#input\_oidc\_token\_endpoint) | Token endpoint of the identity provider. Discovered automatically when `oidc_endpoint_discovery` is `true`. | `string` | `null` | no |
| <a name="input_oidc_user_info_endpoint"></a> [oidc\_user\_info\_endpoint](#input\_oidc\_user\_info\_endpoint) | User info endpoint of the identity provider. Discovered automatically when `oidc_endpoint_discovery` is `true`. | `string` | `null` | no |
| <a name="input_port"></a> [port](#input\_port) | Port on which the load balancer listens. ALB authentication actions require a TLS-terminated listener. | `number` | `443` | no |
| <a name="input_protocol"></a> [protocol](#input\_protocol) | Protocol for connections from clients to the load balancer. Must be `HTTPS` when the default action authenticates users. | `string` | `"HTTPS"` | no |
| <a name="input_rules"></a> [rules](#input\_rules) | Map of listener rules keyed by an arbitrary, stable identifier. Each rule<br/>combines a set of conditions with an action, optionally preceded by an<br/>`authenticate-oidc` action. Set `authenticate = false` to create a bypass<br/>rule (health checks, machine-to-machine APIs, ...). | <pre>map(object({<br/>    priority     = optional(number)<br/>    authenticate = optional(bool, true)<br/>    tags         = optional(map(string), {})<br/><br/>    conditions = object({<br/>      host_header = optional(object({<br/>        values       = optional(list(string))<br/>        regex_values = optional(list(string))<br/>      }))<br/>      path_pattern = optional(object({<br/>        values       = optional(list(string))<br/>        regex_values = optional(list(string))<br/>      }))<br/>      http_request_method = optional(object({<br/>        values = list(string)<br/>      }))<br/>      source_ip = optional(object({<br/>        values = list(string)<br/>      }))<br/>      http_headers = optional(list(object({<br/>        name         = string<br/>        values       = optional(list(string))<br/>        regex_values = optional(list(string))<br/>      })), [])<br/>      query_strings = optional(list(object({<br/>        key   = optional(string)<br/>        value = string<br/>      })), [])<br/>    })<br/><br/>    action = object({<br/>      type             = optional(string, "forward")<br/>      target_group_arn = optional(string)<br/>      forward = optional(object({<br/>        target_groups = list(object({<br/>          arn    = string<br/>          weight = optional(number)<br/>        }))<br/>        stickiness = optional(object({<br/>          enabled  = optional(bool, true)<br/>          duration = optional(number, 3600)<br/>        }))<br/>      }))<br/>      redirect = optional(object({<br/>        status_code = optional(string, "HTTP_302")<br/>        host        = optional(string)<br/>        path        = optional(string)<br/>        port        = optional(string)<br/>        protocol    = optional(string)<br/>        query       = optional(string)<br/>      }))<br/>      fixed_response = optional(object({<br/>        content_type = optional(string, "text/plain")<br/>        message_body = optional(string)<br/>        status_code  = optional(string, "200")<br/>      }))<br/>    })<br/><br/>    oidc = optional(object({<br/>      scope                               = optional(string)<br/>      session_cookie_name                 = optional(string)<br/>      session_timeout                     = optional(number)<br/>      on_unauthenticated_request          = optional(string)<br/>      authentication_request_extra_params = optional(map(string))<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_ssl_policy"></a> [ssl\_policy](#input\_ssl\_policy) | Name of the SSL policy for the listener. Only used when `protocol` is `HTTPS`. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources created by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_listener_arn"></a> [listener\_arn](#output\_listener\_arn) | ARN of the listener carrying the OIDC configuration (created or provided). |
| <a name="output_listener_created"></a> [listener\_created](#output\_listener\_created) | Whether the listener is managed by this module. |
| <a name="output_listener_id"></a> [listener\_id](#output\_listener\_id) | ID of the listener created by this module. |
| <a name="output_oidc_discovery_url"></a> [oidc\_discovery\_url](#output\_oidc\_discovery\_url) | OpenID Connect discovery document URL used to resolve the endpoints. |
| <a name="output_oidc_endpoints"></a> [oidc\_endpoints](#output\_oidc\_endpoints) | Resolved OIDC endpoints used in the authentication actions. |
| <a name="output_oidc_issuer"></a> [oidc\_issuer](#output\_oidc\_issuer) | Issuer identifier used in the authentication actions. |
| <a name="output_oidc_redirect_uris"></a> [oidc\_redirect\_uris](#output\_oidc\_redirect\_uris) | Redirect (callback) URIs to whitelist at the identity provider, derived from `callback_domains` and the host header conditions of authenticated rules. |
| <a name="output_oidc_session_cookie_name"></a> [oidc\_session\_cookie\_name](#output\_oidc\_session\_cookie\_name) | Base name of the session cookie set by the load balancer. AWS appends a shard index (`-0`, `-1`, ...) to it. |
| <a name="output_rule_arns"></a> [rule\_arns](#output\_rule\_arns) | Map of listener rule ARNs, keyed by the `rules` input key. |
| <a name="output_rule_ids"></a> [rule\_ids](#output\_rule\_ids) | Map of listener rule IDs, keyed by the `rules` input key. |
| <a name="output_rule_priorities"></a> [rule\_priorities](#output\_rule\_priorities) | Map of the effective priorities assigned to each listener rule. |
<!-- END_TF_DOCS -->

## Development

```bash
terraform fmt -recursive && terraform init -backend=false && terraform validate && terraform test
```

The test suite runs entirely on mocked providers, so no AWS account and no
credentials are needed. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache 2.0. See [LICENSE](LICENSE).
