# Existing listener

Attaches rules to an HTTPS listener managed elsewhere, mixing authenticated and
unauthenticated paths:

| Priority | Path | Authenticated |
| --- | --- | --- |
| 10 | `/healthz`, `/readyz` | no, answered by the load balancer |
| 20 | `/api/*` from `10.0.0.0/8` | no, the backend checks its own tokens |
| 50 | `/admin/*` | yes, 15 minute session and forced re-login |
| 100 | everything else on the domain | yes |

Priorities are evaluated in ascending order, so the bypass rules must be
numbered below the authenticated ones.

## Usage

```bash
terraform init
terraform apply \
  -var 'listener_arn=arn:aws:elasticloadbalancing:...' \
  -var 'web_target_group_arn=arn:aws:elasticloadbalancing:...' \
  -var 'api_target_group_arn=arn:aws:elasticloadbalancing:...' \
  -var 'oidc_client_id=...' \
  -var 'oidc_client_secret=...'
```

Run `terraform destroy` when you are done. This example creates real resources
that may cost money.
