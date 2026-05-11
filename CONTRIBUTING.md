# Contributing

Thanks for your interest in contributing! Here's everything you need to know.

## Reporting Bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) when opening an issue. Always redact API tokens, zone IDs, and any other sensitive values from logs before posting.

## Suggesting Features

Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).

## Submitting Pull Requests

1. Fork the repository and create a branch from `dev`.
2. Make your changes.
3. Test locally using `DRY_RUN_MODE=true` before submitting.
4. Ensure the Bash script passes [ShellCheck](https://www.shellcheck.net/).
5. Open a pull request against the `dev` branch.

## Development Guidelines

- Keep the container image minimal (Alpine-based, no unnecessary packages).
- Bash code must pass `shellcheck` with no warnings.
- API tokens must **never** appear in log output.
- All `curl` calls should include timeout flags.
- Document any new configuration options in both `cloudflare-ddns-config.yaml` and `README.md`.

## Branch Structure

| Branch | Purpose |
|--------|---------|
| `main` | Stable, tagged releases |
| `dev` | Active development — PRs go here |
| `latest` | Triggers production Docker image build |
