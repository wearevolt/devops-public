# devops-public

Public repository for shared DevOps scripts and utilities used across WeareVolt projects. No sensitive data or internal-only tooling; everything here is safe to share and reuse.

## Contents

| Script | Description |
|--------|-------------|
| [setup-moneyball-aws-sso.sh](./setup-moneyball-aws-sso.sh) | Configures AWS SSO profile and EKS kubeconfig for Moneyball (QA, Staging, Production). |
| [setup-internal-aws-sso.sh](./setup-internal-aws-sso.sh) | Configures AWS SSO profile for WeareVolt internal accounts (spice, pjc, alex, internal) via [wearevolt.awsapps.com](https://wearevolt.awsapps.com/start/#/). |

## setup-moneyball-aws-sso.sh

- **Purpose:** One-time setup of AWS SSO and kubectl access to Moneyball EKS clusters.
- **Requirements:** `aws` CLI and `kubectl` installed; access to Moneyball AWS SSO.
- **Usage:**
  ```bash
  chmod +x setup-moneyball-aws-sso.sh
  ./setup-moneyball-aws-sso.sh
  ```
- **Actions:** Writes SSO session and profile to `~/.aws/config`, runs `aws sso login`, updates kubeconfig for the chosen environment. Prompts for environment (1=QA, 2=Staging, 3=Production).

## setup-internal-aws-sso.sh

- **Purpose:** One-time setup of AWS SSO for WeareVolt internal accounts (spice, pjc, alex, internal). Uses SSO portal [wearevolt.awsapps.com](https://wearevolt.awsapps.com/start/#/).
- **Requirements:** `aws` CLI; access to WeareVolt AWS SSO. Account IDs are pre-filled (Spice, WAV-PJC, Alex, WAV-COMMON); override via `ACCOUNT_ID_SPICE`, `ACCOUNT_ID_PJC`, `ACCOUNT_ID_ALEX`, `ACCOUNT_ID_INTERNAL` if needed.
- **Usage:**
  ```bash
  chmod +x setup-internal-aws-sso.sh
  ./setup-internal-aws-sso.sh
  ```
- **Actions:** Writes SSO session `wearevolt-internal` and chosen profile to `~/.aws/config`, runs `aws sso login`, verifies identity. EKS kubeconfig step is commented out; uncomment and set `CLUSTER_NAME` in the script if the account has EKS.

## Contributing

Add new scripts here when they are:

- Generic enough to be useful across teams or projects
- Free of secrets, internal URLs, or account-specific data (or clearly parameterized)
- Documented in this README with purpose, requirements, and usage

## Changelog

- **2025-02-11** — Renamed `setup-aws-sso.sh` to `setup-moneyball-aws-sso.sh`. Added `setup-internal-aws-sso.sh` for WeareVolt internal SSO (profiles: spice, pjc, alex, internal; SSO at https://wearevolt.awsapps.com/start/#/). README updated.
- **2025-02-11** — Repository created. Added `setup-aws-sso.sh` (moved from moneyball-devops/devops). README added with description that this repo stores all public DevOps scripts.
---

*This repository holds all public DevOps scripts intended for broad use.*
