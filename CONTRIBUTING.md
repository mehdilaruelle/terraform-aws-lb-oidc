# Contributing

Thanks for taking the time to contribute.

## Getting started

Requirements: [Terraform](https://developer.hashicorp.com/terraform/downloads)
>= 1.9, [tflint](https://github.com/terraform-linters/tflint),
[terraform-docs](https://terraform-docs.io/) and, optionally,
[pre-commit](https://pre-commit.com/). CI pins terraform-docs to v0.24.0, so
install that version to avoid spurious diffs.

```bash
pre-commit install
```

## Local checks

Everything CI runs is reproducible locally, and none of it needs an AWS
account:

```bash
make all
```

Or one target at a time:

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform test
tflint --init --recursive && tflint --recursive --minimum-failure-severity=error
terraform-docs .
```

The test suite in [`tests/`](tests) uses `mock_provider`, so `terraform test`
plans against fake AWS and HTTP providers. Add a `run` block for any behaviour
you change:

- `tests/defaults.tftest.hcl` — listener and default action wiring
- `tests/discovery.tftest.hcl` — OIDC endpoint discovery
- `tests/rules.tftest.hcl` — listener rules, conditions and per-rule overrides
- `tests/validation.tftest.hcl` — input validation and preconditions

Examples are validated in CI too, so keep them in sync when you add an input.

## Documentation

The input and output tables in `README.md` are generated. Run `terraform-docs .`
(or let pre-commit do it) after touching `variables.tf` or `outputs.tf` —
CI fails on a stale README.

## Commit and pull request titles

Releases are cut by [release-please](https://github.com/googleapis/release-please)
from [Conventional Commits](https://www.conventionalcommits.org/). Pull requests
are squash-merged, so the **pull request title** is what matters:

```
feat: add support for weighted forward actions
fix: keep per-rule scope override when session timeout is unset
docs: document the session cookie sharding limit
```

Use `feat!:` or a `BREAKING CHANGE:` footer for anything that changes the module
interface — it bumps the major version.

## Releasing

Maintainers only: merging the release pull request opened by release-please tags
the version and publishes the release. The Terraform Registry picks up the new
tag automatically.
