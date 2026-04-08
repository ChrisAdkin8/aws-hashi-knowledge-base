# Terraform Code Analysis Report

**Date:** 2026-04-07
**Scope:** terraform/ (full repo)
**Files scanned:** 14 .tf files across 2 modules + 1 root, 2 .tfvars files
**Focus:** all
**Mode:** static
**Health Grade:** C (58/100)

---

## Executive Summary

The codebase has a clean module structure after recent refactoring into `hashicorp-kendra-rag` and `neptune` inline modules. However, a **state file exists on disk** at the repo root, the `.terraform.lock.hcl` is gitignored (preventing provider pinning across environments), and several IAM policies use overly broad permissions. The CI pipeline is solid (validate, Trivy, ShellCheck, Python tests) but the GitHub Actions workflow references an outdated region (`us-west-2`).

**Finding counts by urgency:**

| Urgency | Count |
|---------|-------|
| CRITICAL | 1 |
| HIGH | 5 |
| MEDIUM | 6 |
| LOW | 3 |
| INFO | 3 |

---

## 1. Security Posture

### CRITICAL

- **[S-001] State file on disk at repo root** — `terraform.tfstate` | Blast: infrastructure-wide
  A `terraform.tfstate` file exists at `/Users/chris.adkin/Projects/aws-hashi-knowledge-base/terraform.tfstate`. State files contain decrypted secrets for every managed resource (IAM keys, bucket policies, etc.). Even if gitignored, it risks accidental commit or exposure.
  **Fix:** Delete the file (`rm terraform.tfstate`) after confirming state is safely in the S3 remote backend. Add `terraform.tfstate` to `.gitignore` at the repo root level (already present but verify path coverage).

### HIGH

- **[S-002] GitHub Actions IAM policy grants `Action: ["*"]` on `Resource: "*"`** — `modules/hashicorp-kendra-rag/iam.tf:198` | Blast: infrastructure-wide
  The `github_actions` IAM role policy is a full admin wildcard. Even behind an OIDC condition, this is excessive.
  **Fix:** Scope to the specific actions needed (Terraform state read/write, resource provisioning in target services). At minimum restrict to the services used: `s3:*`, `kendra:*`, `codebuild:*`, `states:*`, `events:*`, `iam:*`, `logs:*`, `sns:*`, `scheduler:*`.

- **[S-003] `.terraform.lock.hcl` is gitignored** — `.gitignore` | Blast: infrastructure-wide
  Both `terraform/.terraform.lock.hcl` and `.terraform.lock.hcl` are in `.gitignore`. The lock file MUST be committed to ensure all contributors and CI use the same provider builds with verified hashes.
  **Fix:** Remove both `.terraform.lock.hcl` lines from `.gitignore` and commit the lock file.

- **[S-004] KMS permissions use `Resource: ["*"]`** — `modules/hashicorp-kendra-rag/iam.tf:57-60,93-94` | Blast: module
  Both the Kendra and CodeBuild IAM policies grant `kms:Decrypt` and `kms:GenerateDataKey` on all KMS keys. The Kendra policy has a `ViaService` condition but the CodeBuild policy does not.
  **Fix:** Add `kms:ViaService` condition to the CodeBuild KMS statement. Ideally pin both to the specific KMS key ARN.

- **[S-005] EventBridge rules permission uses `Resource: "*"`** — `modules/hashicorp-kendra-rag/iam.tf:157-161` | Blast: module
  The Step Functions IAM policy grants `events:PutTargets`, `events:PutRule`, etc. on `"*"`. While the second ARN entry is specific, the first wildcard overrides it.
  **Fix:** Remove the `"*"` entry and keep only the specific rule ARN.

- **[S-006] CI workflow hardcodes `us-west-2` but default region is `us-east-1`** — `.github/workflows/terraform.yml:24` | Blast: environment
  The `aws-region: us-west-2` in the GitHub Actions workflow doesn't match the default region (`us-east-1`) used everywhere else. This could cause OIDC credential issues or region mismatch during CI validate.
  **Fix:** Change line 24 to `aws-region: us-east-1`.

---

## 2. DRY and Code Reuse

### MEDIUM

- **[D-001] `data.aws_caller_identity.current` duplicated across both modules** — `modules/hashicorp-kendra-rag/data.tf:1`, `modules/neptune/data.tf:1` | Blast: module
  Both modules independently call `aws_caller_identity`. This is not a correctness issue but adds an API call per module. Consider passing `account_id` as a variable from the root module.
  **Fix:** Add `variable "account_id"` to both modules, look up once in root `main.tf`, pass to both modules.

- **[D-002] `terraform.tfvars.example` references stale variables** — `terraform/terraform.tfvars.example:9-14` | Blast: single-resource
  The example file references `knowledge_base_name`, `collection_name`, `chunk_size`, `chunk_overlap_pct` which no longer exist in `variables.tf` after the Kendra migration.
  **Fix:** Update to reflect current variables (`kendra_edition`, `create_neptune`, etc.).

---

## 3. Style and Conventions

### MEDIUM

- **[Y-001] `modules/neptune/main.tf` has formatting issues** — `modules/neptune/main.tf` | Blast: single-resource
  `terraform fmt -check` flagged this file. Alignment of `=` in the `aws_neptune_cluster` resource was inconsistent.
  **Fix:** Already auto-fixed by `terraform fmt` during this analysis.

### LOW

- **[Y-002] Inconsistent variable ordering** — `terraform/variables.tf` | Blast: single-resource
  Root `variables.tf` groups variables by module (good) but neither group follows required-first ordering. `repo_uri` (no default, required) appears after optional variables.
  **Fix:** Move required variables to the top of each group.

- **[Y-003] Neptune module `iam.tf` is a placeholder comment** — `modules/neptune/iam.tf` | Blast: single-resource
  The file contains only a comment. While acceptable, an empty file or no file would be cleaner than a placeholder.
  **Fix:** Remove the file or add IAM resources when Neptune integration is wired in.

---

## 4. Robustness

### HIGH

- **[R-001] No `lifecycle { prevent_destroy }` on stateful resources** — multiple files | Blast: module
  The Kendra index (`aws_kendra_index.main`), S3 bucket (`aws_s3_bucket.rag_docs`), and Neptune cluster (`aws_neptune_cluster.main`) have no destruction protection via Terraform lifecycle blocks. The S3 bucket also has `force_destroy = true`. Neptune has a `deletion_protection` variable but it defaults to `false`.
  **Fix:** Add `lifecycle { prevent_destroy = true }` to the Kendra index. Remove `force_destroy = true` from the S3 bucket (or gate it behind a variable). Default `deletion_protection` to `true` for Neptune.

### MEDIUM

- **[R-002] No `validation` blocks on dangerous inputs** — `modules/neptune/variables.tf`, `modules/hashicorp-kendra-rag/variables.tf` | Blast: module
  `region`, `kendra_edition`, `instance_class`, and `neptune_subnet_ids` accept any string/list without validation. A typo could cause cryptic provider errors.
  **Fix:** Add validation blocks, e.g.:
  ```hcl
  variable "kendra_edition" {
    validation {
      condition     = contains(["DEVELOPER_EDITION", "ENTERPRISE_EDITION"], var.kendra_edition)
      error_message = "Must be DEVELOPER_EDITION or ENTERPRISE_EDITION."
    }
  }
  ```

- **[R-003] Provider version constraint is wide** — `versions.tf:5` | Blast: infrastructure-wide
  `aws = "~> 5.60"` allows 5.60 through 5.999. Minor provider versions occasionally introduce breaking changes for specific resources.
  **Fix:** Tighten to `~> 5.100` (current installed version) for stability.

- **[R-004] `required_version = ">= 1.10, < 2.0"` is broad** — `versions.tf:2` | Blast: infrastructure-wide
  Running Terraform v1.14.5 but the constraint allows any 1.x from 1.10+. This is acceptable but note that features used (like module `count`) require >= 1.1.
  **Fix:** Consider tightening to `>= 1.10, < 1.15` for predictability.

---

## 5. Simplicity

### INFO

- **[X-001] Neptune module `locals.tf` contains a single local** — `modules/neptune/locals.tf` | Blast: single-resource
  `account_id` is the only local, used nowhere in the module currently (no IAM resources reference it). It was extracted from the pre-refactor code and is dead code in the Neptune module.
  **Fix:** Remove `locals.tf` and `data.tf` from the Neptune module until they're needed.

---

## 6. Operational Readiness

### MEDIUM

- **[O-001] No common tags/labels local** — multiple files | Blast: module
  Tags are applied via the provider `default_tags` block (good) but modules cannot add resource-specific tags. There's no `tags` variable or `local.common_tags` pattern.
  **Fix:** Add a `tags` variable to each module for resource-specific overrides.

### INFO

- **[O-002] CloudWatch monitoring is conditional** — `modules/hashicorp-kendra-rag/main.tf:80-120` | Blast: module
  Alerting only deploys when `notification_email != ""`. This is a reasonable default but means a deployment without email has zero monitoring. Worth noting.

---

## 7. CI/CD and Testing Maturity

### LOW

- **[C-001] No pre-commit framework** — repo root | Blast: environment
  No `.pre-commit-config.yaml`. The CI pipeline catches formatting and security issues, but local pre-commit hooks would catch them faster.
  **Fix:** Add pre-commit with `terraform_fmt`, `terraform_validate`, `detect-secrets` hooks.

### INFO

- **[C-002] CI pipeline is well-structured** — `.github/workflows/terraform.yml` | Blast: n/a
  The workflow runs `terraform fmt -check`, `terraform validate`, Trivy security scan, ShellCheck, and Python unit tests. This is a strong CI setup.

---

## 8. Cross-Module Contracts

### MEDIUM

- **[M-001] Neptune module outputs are conditionally accessed but not null-safe in all callers** — `terraform/outputs.tf:55-70` | Blast: module
  Root outputs use `var.create_neptune ? module.neptune[0].X : null` — correct. But if a future module consumes these outputs without the conditional guard, it will fail. Consider using `try()` for defense in depth.

---

## 9. Stack-Specific Findings

No Vault, Consul, GKE, or Helm resources detected. No stack-specific findings.

---

## 10. CLAUDE.md Compliance

CLAUDE.md specifies:
- "Smallest change that works" — ✅ Module structure is clean and minimal.
- "Read existing code before modifying" — ✅ Not a code finding.
- No quantitative Terraform-specific rules documented.

No compliance violations detected.

---

## 11. Suppressed Findings

No `.tf-analyze-ignore.yaml` found. No inline suppressions detected.

---

## 12. Positive Findings

- **Clean module decomposition.** The split into `hashicorp-kendra-rag` and `neptune` modules with `iam.tf`, `s3.tf`, `kendra.tf`, `data.tf`, `locals.tf` is well-structured and follows conventions.
- **Provider `default_tags` usage.** All resources get `Project` and `ManagedBy` tags automatically.
- **Remote S3 backend with lock files.** State is configured for remote storage with `use_lockfile = true`.
- **Neptune is gated behind a flag.** `create_neptune = false` by default prevents accidental deployment of expensive resources.
- **CI/CD pipeline coverage.** Trivy security scanning, ShellCheck, and Python tests in CI is above average for a Terraform repo.
- **S3 bucket hardening.** Versioning, lifecycle rules, SSE, public access block all present.

---

## 13. Recommended Action Plan

| Priority | Finding | Section | Effort | Blast Radius | Description |
|----------|---------|---------|--------|--------------|-------------|
| 1 | S-001 | Security | Small | infrastructure-wide | Delete `terraform.tfstate` from repo root after confirming remote state |
| 2 | S-003 | Security | Small | infrastructure-wide | Un-gitignore `.terraform.lock.hcl` and commit it |
| 3 | S-002 | Security | Medium | infrastructure-wide | Scope GitHub Actions IAM policy from `*` to specific services |
| 4 | S-006 | Security | Small | environment | Fix CI workflow region `us-west-2` → `us-east-1` |
| 5 | S-004+S-005 | Security | Medium | module | Tighten KMS and EventBridge IAM wildcards |
| 6 | R-001 | Robustness | Small | module | Add `prevent_destroy` to Kendra index, S3 bucket; default Neptune `deletion_protection = true` |
| 7 | R-002 | Robustness | Small | module | Add `validation` blocks to region, edition, instance class |
| 8 | D-002 | DRY | Small | single-resource | Update `terraform.tfvars.example` for current variables |
| 9 | R-003 | Robustness | Small | infrastructure-wide | Tighten provider version to `~> 5.100` |
| 10 | D-001 | DRY | Small | module | Pass `account_id` as variable instead of duplicating data source |
| 11 | C-001 | CI/CD | Small | environment | Add `.pre-commit-config.yaml` |
| 12 | O-001 | Ops | Small | module | Add `tags` variable to modules |

### Related Findings

- S-004 + S-005: Both are IAM wildcard issues in the Kendra-RAG module — address together
- S-001 + S-003: Both relate to state/lock hygiene — address together as a security hardening pass
- R-001 + R-002: Robustness gaps — `prevent_destroy` and input validation should be added in the same PR
