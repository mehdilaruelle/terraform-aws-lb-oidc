# Complete

Self-contained deployment: a VPC with two public subnets, an Application Load
Balancer, two target groups, an HTTP listener redirecting to HTTPS, and the
authenticated HTTPS listener built by the module.

It exercises most of the module surface:

- OIDC default action with endpoint discovery
- an unauthenticated fixed-response health check
- an unauthenticated API path matched on an `Authorization` header
- an admin path with a weighted forward, stickiness, a short session and
  `on_unauthenticated_request = "deny"`

The load balancer sits in public subnets because it must reach the identity
provider over the internet. Private subnets work too, behind a NAT gateway.

## Usage

You need an ACM certificate covering the domain you point at the load balancer:

```bash
terraform init
terraform apply \
  -var 'certificate_arn=arn:aws:acm:...' \
  -var 'domain_name=app.example.com' \
  -var 'oidc_client_id=...' \
  -var 'oidc_client_secret=...'
```

Then create a DNS record for `domain_name` pointing at the
`load_balancer_dns_name` output, and register `oidc_redirect_uris` in your
identity provider application.

Run `terraform destroy` when you are done. This example creates real resources
that may cost money.
