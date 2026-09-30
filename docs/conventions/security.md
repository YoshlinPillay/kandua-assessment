# Security rules

- **No credentials in git.** Real values live in `.env` (gitignored) locally and in AWS SSM Parameter Store
  (SecureString) in the cloud. `.env.example` holds placeholders only (`changeme`). `gitleaks` runs in
  pre-commit and CI.
- The agent must not read or print `.env` contents. A PreToolUse hook blocks agent edits to `.env` and
  `*.tfstate`.
- **Least privilege DB roles**:
  - `juan_admin` — owner, used by dlt/dbt only.
  - `juan_reader` — `SELECT` on `core` and `marts` only. This is the role shared with reviewers, BI and Cube.
  - The Lightdash and Cube service connections use `juan_reader`.
- **AWS**:
  - GitHub Actions authenticates with OIDC (no long-lived keys in GitHub secrets).
  - RDS is not publicly accessible except through a security group allowlist or SSM port forwarding,
    as documented in the README.
  - EC2 exposes only 80/443. Admin access goes through SSM Session Manager (no open port 22).
  - An AWS Budgets alert is configured. The teardown command is documented.
- **LLM (chat app)**:
  - The Anthropic API key comes from env/SSM.
  - The model gets read-only tools (Cube `/meta`, `/load`) and can't run raw SQL.
  - The tool-call results the model sees are the only data it may cite.
  - The system prompt forbids fabricating numbers. The golden-question tests check this.
- Reviewer credentials and public URLs go in the delivered answers document, **never** in the repo.
