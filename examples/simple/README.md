# Simple

Adds an HTTPS listener that authenticates every request through an OIDC provider
before forwarding it to an existing target group. Only the issuer is configured:
the endpoints come from the provider discovery document.

## Usage

```bash
terraform init
terraform apply \
  -var 'load_balancer_arn=arn:aws:elasticloadbalancing:...' \
  -var 'target_group_arn=arn:aws:elasticloadbalancing:...' \
  -var 'certificate_arn=arn:aws:acm:...' \
  -var 'oidc_client_id=...' \
  -var 'oidc_client_secret=...'
```

Register the value of the `oidc_redirect_uris` output as the callback URL of
your identity provider application before hitting the load balancer.

Run `terraform destroy` when you are done. This example creates real resources
that may cost money.
