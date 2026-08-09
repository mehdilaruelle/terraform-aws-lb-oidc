# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's [private vulnerability reporting](https://github.com/your-org/terraform-aws-lb-oidc/security/advisories/new)
instead. You should get an acknowledgement within a few days.

## Scope

This module configures AWS Application Load Balancer authentication actions. In
practice that means:

- **In scope**: the module generating an insecure configuration — leaking the
  client secret into non-sensitive outputs, applying an authentication action to
  a rule that was meant to be protected, weakening the negotiated TLS policy.
- **Out of scope**: misconfiguration of your own identity provider, ALB
  behaviour itself (report to AWS), and the deliberately minimal
  [`examples/`](examples) which are not hardened for production.

## Handling the client secret

`oidc_client_secret` is marked sensitive, but it is still written in clear text
to the Terraform state. Encrypt your state, restrict access to it, and source
the value from a secret manager rather than a `.tfvars` file committed to git.
