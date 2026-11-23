# Secure CI/CD Pipeline for GitHub Actions

A ready-to-use GitHub Actions pipeline with **SAST, SCA and DAST** security scans, a **severity gate**, **PR approval** for `main`, and a **manual approval** before production. The `dev` branch has no restrictions.

| Scan | Tool | What it checks |
|---|---|---|
| **SAST** | [Snyk Code](https://snyk.io/product/snyk-code/) | Your own source code |
| **SCA** | [Snyk Open Source](https://snyk.io/product/open-source-security-management/) + [Snyk Container](https://snyk.io/product/container-vulnerability-management/) | Third-party libraries and the Docker image |
| **DAST** | [OWASP ZAP](https://www.zaproxy.org/) baseline | The running app (headers, cookies, common web issues) |

## How it works

```
push to dev ──► build ──► smoke test ──► deploy to DEV           (no gates)

PR dev → main ──► SAST + SCA + DAST ──► reviewer approves ──► merge
                  (fails if > 3 high)

merge to main ──► SAST + SCA + DAST again ──► ⏸ prod approval ──► deploy to PROD
```

**The gate:** SAST and SCA are counted separately. A scan fails only when it finds **more than 3** unique **high or critical** findings. With 3 or fewer it passes, and the pipeline goes on to approval. Medium and low findings never block. You can change the limit with `MAX_HIGH_FINDINGS`.

Findings also show up in your repo's **Security → Code scanning** tab.

## Files

```
.github/workflows/dev.yml             push to dev → build, smoke test, deploy (no gates)
.github/workflows/security-scans.yml  SAST + SCA + DAST with the gate (reusable)
.github/workflows/prod.yml            merge to main → scans → manual approval → deploy
.zap/rules.tsv                        ZAP findings you have reviewed and accepted
scripts/setup-repo.sh                 one-time repo setup (environments, rules)
src/, Dockerfile                      a tiny sample Java API. Replace it with your app.
```

## Quick start

### 1. Get your own copy
Click **Use this template → Create a new repository**, or **Fork**. Then replace `src/` and `Dockerfile` with your own app.

Your app must build with `docker build` and answer HTTP on its port. If it isn't on port `8080`, or `/` doesn't return 200, set the variables in [Configuration](#configuration).

### 2. Set up Snyk (free)
1. Sign up at [app.snyk.io](https://app.snyk.io) (GitHub login works).
2. **Settings → Snyk Code → Enable Snyk Code**, then save. SAST fails without this.
3. Copy your **Organization ID** (Settings → General).
4. Copy your **Auth Token** (Account settings → General → Auth Token).

### 3. Add the token to GitHub
```bash
gh secret set SNYK_TOKEN --repo <you>/<repo>
```
Or use **Settings → Secrets and variables → Actions → New repository secret** with the name `SNYK_TOKEN`.

### 4. Run the setup script
This needs the [GitHub CLI](https://cli.github.com/), signed in as a repo admin (`gh auth login`):
```bash
bash scripts/setup-repo.sh --snyk-org <your-snyk-org-id>
```
Options: `--reviewer <login>` (who approves prod; default is you), `--approvals <n>` (PR approvals; default 1), `--admin-bypass` (lets admins merge their own PRs once scans pass; useful if you're the only maintainer).

On Windows, run it in Git Bash. If `gh` isn't found:
`GH="/c/Program Files/GitHub CLI/gh.exe" bash scripts/setup-repo.sh ...`

<details>
<summary>Prefer to click through the settings yourself?</summary>

- **Settings → Environments**
  - `development`: no rules.
  - `production`: tick **Required reviewers** and add yourself. Under **Deployment branches**, choose *Selected branches* and add `main`.
- **Settings → Rules → Rulesets → New branch ruleset** named `protect-main`, targeting the default branch:
  - Restrict deletions, Block force pushes
  - Require a pull request (1 approval, dismiss stale approvals)
  - Require status checks: `SAST (Snyk Code)`, `SCA (Snyk)`, `DAST (OWASP ZAP)`
- **Settings → Secrets and variables → Actions → Variables**: `SNYK_ORG` = your Snyk Organization ID
- Create a `dev` branch.
</details>

### 5. Use it
```bash
git checkout dev
# ...make changes...
git push              # deploys to DEV
```
Then open a PR from `dev` to `main`. After the scans pass and the PR is approved, merge it. Then go to **Actions → Prod Deploy → Review deployments → Approve and deploy**.

### 6. Add your real deploy steps
Both `dev.yml` and `prod.yml` end with a placeholder `Deploy` step. Replace it with your own: push to a registry, `kubectl`, `aws ecs update-service`, `az webapp`, and so on. Store credentials as **environment secrets** on `development` / `production`.

## Configuration

Set these as **repository variables** (Settings → Secrets and variables → Actions → Variables). All are optional.

| Variable | Default | Meaning |
|---|---|---|
| `MAX_HIGH_FINDINGS` | `3` | A scan fails when it finds **more than** this many high/critical issues |
| `SNYK_ORG` | (account default) | Snyk Organization ID. Set it if Snyk says *"Snyk Code is not enabled"* or shows an empty org |
| `APP_PORT` | `8080` | Port your container listens on |
| `HEALTH_PATH` | `/` | Path that returns 2xx once the app is up |
| `DAST_PATH` | `/` | Path ZAP starts scanning from |
| `DOCKER_CONTEXT` | `.` | Docker build context |
| `DOCKERFILE` | `Dockerfile` | Path to the Dockerfile |
| `RUN_DAST` | `true` | Set to `false` to skip DAST (for example, for non-HTTP apps) |
| `PYTHON_VERSION` | `3.11` | Python used to install `requirements.txt` so Snyk can resolve it |
| `SNYK_MONITOR` | `true` | Send results from the default branch (and manual runs) to your Snyk dashboard. Set to `false` to report to GitHub only |

## Use the scans from another repo (no copy needed)

```yaml
# .github/workflows/security.yml in your repo
name: Security
on:
  pull_request:
    branches: [main]
jobs:
  security:
    uses: dealindia/secure-cicd-pipeline/.github/workflows/security-scans.yml@v1
    permissions:
      contents: read
      security-events: write
    with:
      max-high-findings: '3'
      app-port: '3000'
      health-path: /health
    secrets:
      SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
```

Inputs: `max-high-findings`, `app-port`, `health-path`, `dast-path`, `docker-context`, `dockerfile`, `run-dast`, `snyk-org`, `python-version`, `snyk-monitor`. Each falls back to the repo variable of the same name, then to the default above.

The check names in the caller repo become `security / SAST (Snyk Code)` and so on. Use those names in your branch ruleset.

## Where to see the results

| Where | What you get |
|---|---|
| **Security → Code scanning** in your repo | Every SAST and SCA finding, with the file, the CVE and the fix. For PR results, filter with `pr:<number>` or `branch:dev` |
| **Actions → the run → Summary** | The gate result for each scan, links to the Snyk dashboard, and the **`zap_scan`** artifact (a full ZAP HTML report) |
| **[app.snyk.io](https://app.snyk.io) → Projects** | Snyk's dashboard: history, trends, fix suggestions and alerts for new vulnerabilities. Updated on every merge to the default branch and on manual runs (**Actions → Security Scans → Run workflow**). PR results are not sent |

## Accepting a DAST finding

If ZAP flags something you've reviewed and accept, add a tab-separated line to `.zap/rules.tsv`:
```
10049	IGNORE	(Non-Storable Content) API sets Cache-Control: no-store on purpose
```

## Good to know

- **Public vs private repos:** required reviewers on environments and branch rulesets are free on **public** repos. On private repos they need GitHub Pro, Team or Enterprise.
- **You can't approve your own PR.** If you're the only maintainer, use `--admin-bypass` or invite a second reviewer.
- **Snyk free plan** has monthly test limits. Each PR plus its merge uses about two tests per scan type, and sending results to the dashboard uses one more Snyk Code test per merge.
- **`main` or `master`:** the workflows run for either name, so you don't have to rename your default branch.
- **Python and Node:** before Snyk Open Source runs, the pipeline installs `requirements*.txt` packages and creates a `package-lock.json` where one is missing. Snyk needs these to see the full dependency tree.
- **No dependency manifest?** If your project has no `pom.xml`, `package.json`, `requirements.txt` or similar, Snyk Open Source has nothing to scan and skips itself. Snyk Container still scans the image.
- Third-party actions are pinned to commit SHAs where tags have been unreliable. Keep them updated (for example with Dependabot).

## License

[MIT](LICENSE)
