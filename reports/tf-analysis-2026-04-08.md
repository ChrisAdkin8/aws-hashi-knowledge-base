# Terraform Code Analysis Report

**Date:** 2026-04-08
**Scope:** terraform/ (full repo)
**Files scanned:** 30 .tf files across 3 modules + 1 root + 1 bootstrap root, 2 .tfvars files
**Focus:** all
**Mode:** static
**Health Grade:** B (76/100)

---

## Executive Summary

Significant progress since the 2026-04-07 report. The state file leak (S-001) is resolved, the GitHub Actions IAM policy is scoped per-service (no more `Action: "*"`), `prevent_destroy` guards are in place on stateful resources, input validation blocks are added to both modules, provider/Terraform versions are tightened, and `account_id` is passed as a variable. The remaining issues are: `.terraform.lock.hcl` files still uncommitted, GitHub Actions IAM uses `Resource: "*"` on every statement, a CI/Terraform version mismatch, stale repo name references from the rename, and the EC2 wildcard in the graph-store CodeBuild policy.

**Finding counts by urgency:**

| Urgency | Count |
|---------|-------|
| CRITICAL | 0 |
| HIGH | 3 |
| MEDIUM | 4 |
| LOW | 3 |
| INFO | 2 |

---

## Delta vs Previous Report (2026-04-07)

| Finding | Status | Notes |
|---------|--------|-------|
| S-001 State file on disk | **FIXED** | `terraform.tfstate` no longer present at repo root |
| S-002 GitHub Actions `Action: ["*"]` | **FIXED** | Actions are now per-service. Resource wildcards remain (see S-002 below) |
| S-003 Lock files not committed | **OPEN** | No longer gitignored, but still untracked — need `git add` |
| S-004 KMS `Resource: ["*"]` | **IMPROVED** | Both Kendra and CodeBuild KMS statements now have `kms:ViaService` condition. Residual risk is LOW |
| S-005 EventBridge `Resource: "*"` | **FIXED** | Specific ARN only in docs-pipeline iam.tf:184 |
| S-006 CI region mismatch | **FIXED** | Now `us-east-1` |
| R-001 No `prevent_destroy` | **FIXED** | Kendra index, both S3 buckets have `prevent_destroy = true`; Neptune defaults `deletion_protection = true` |
| R-002 No validation blocks | **FIXED** | Both modules have validation on region, edition, vpc_id, subnet_ids, instance_class, instance_count, compute_type |
| R-003 Provider version wide | **FIXED** | Tightened to `~> 5.100` |
| R-004 Terraform version broad | **FIXED** | Tightened to `>= 1.10, < 1.15` |
| D-001 Duplicated `aws_caller_identity` | **FIXED** | `account_id` passed from root; data source remains only in root `data.tf` and state-backend `data.tf` |
| D-002 Stale tfvars.example | **FIXED** | Updated for current variables |
| Y-001 Formatting issues | **FIXED** | `terraform fmt -check -recursive` clean |
| Y-002 Variable ordering | **IMPROVED** | Required vars (`repo_uri`) still not first in root `variables.tf`, but structure is logical by section |
| Y-003 Neptune iam.tf placeholder | **FIXED** | Now contains full IAM role/policy definitions |
| X-001 Dead locals in Neptune | **FIXED** | Module restructured as `terraform-graph-store` with used locals |
| O-001 No tags variable | **FIXED** | Both modules accept `tags` variable |
| C-001 No pre-commit | **OPEN** | Still no `.pre-commit-config.yaml` |

**Score change:** C (58) → B (76), +18 points. 14 of 18 findings resolved; 2 improved; 2 open.

---

## 1. Security Posture

### HIGH

- **[S-001] GitHub Actions IAM policy uses `Resource: "*"` on all 10 statements** — `modules/hashicorp-docs-pipeline/iam.tf:257-341` | Blast: infrastructure-wide
  While the previous `Action: ["*"]` is fixed, every statement in the GitHub Actions role policy still uses `Resource = "*"`. This means the OIDC role can manage ANY Kendra index, ANY CodeBuild project, ANY Step Functions state machine, etc. in the account — not just the ones managed by this stack.
  **Fix:** Scope each `Resource` to the specific ARNs or at least to resource-name prefixes. Example:
  ```hcl
  Resource = ["arn:aws:kendra:${var.region}:${var.account_id}:index/*"]
  ```
  For S3, scope to `arn:aws:s3:::hashicorp-rag-*` and `arn:aws:s3:::*-tf-state-*`.

- **[S-002] `.terraform.lock.hcl` files not committed to source control** — `terraform/.terraform.lock.hcl`, `terraform/bootstrap/.terraform.lock.hcl` | Blast: infrastructure-wide
  Lock files exist on disk and are not gitignored, but they have never been committed. Without committed lock files, different contributors and CI get different provider builds with unverified hashes. This is a supply-chain risk.
  **Fix:** `git add terraform/.terraform.lock.hcl terraform/bootstrap/.terraform.lock.hcl && git commit`.

- **[S-003] EC2 wildcard in graph-store CodeBuild IAM** — `modules/terraform-graph-store/iam.tf:47` | Blast: module
  The CodeBuild role grants 7 EC2 networking actions on `Resource = "*"`. While these are required for VPC-attached CodeBuild and cannot be scoped to specific resources (AWS limitation for `ec2:CreateNetworkInterface`), the policy also includes `ec2:CreateNetworkInterfacePermission` which could be scoped to the VPC.
  **Fix:** Add a condition block:
  ```hcl
  Condition = {
    StringEquals = { "ec2:Vpc" = "arn:aws:ec2:${var.region}:${var.account_id}:vpc/${var.vpc_id}" }
  }
  ```
  Note: this is an AWS-documented pattern for CodeBuild VPC access.

### MEDIUM

- **[S-004] KMS permissions still use `Resource: ["*"]` (mitigated by condition)** — `modules/hashicorp-docs-pipeline/iam.tf:62-68,110-116` | Blast: module
  Both Kendra and CodeBuild KMS statements grant `kms:Decrypt` and `kms:GenerateDataKey` on all KMS keys. The `kms:ViaService` condition limits to S3-originated requests, which is good mitigation. However, pinning to the specific KMS key ARN would be defense-in-depth.
  **Fix:** If using a customer-managed KMS key, reference its ARN. If using the default `aws/s3` key, the ViaService condition is sufficient — downgrade to INFO.

---

## 2. DRY and Code Reuse

### MEDIUM

- **[D-001] Stale repo name in `terraform.tfvars` and `terraform.tfvars.example`** — `terraform/terraform.tfvars:2`, `terraform/terraform.tfvars.example:5` | Blast: single-resource
  The `repo_uri` value references the old repository name `hashicorp-bedrock-ai-rag` instead of `aws-hashi-knowledge-base`. The repo was recently renamed.
  - `terraform.tfvars`: `repo_uri = "https://github.com/ChrisAdkin8/hashicorp-bedrock-ai-rag"`
  - `terraform.tfvars.example`: `repo_uri = "https://github.com/your-org/hashicorp-bedrock-ai-rag"`
  **Fix:** Update both files to use the current repo name `aws-hashi-knowledge-base`.

---

## 3. Style and Conventions

### LOW

- **[Y-001] Required variables not ordered first in root `variables.tf`** — `terraform/variables.tf` | Blast: single-resource
  `repo_uri` (no default, required) appears at line 29, after several optional variables. Convention is required-first within each group.
  **Fix:** Move `repo_uri` to the top of the shared section.

- **[Y-002] CI workflow uses `terraform_version: "~1.9"` but repo requires `>= 1.10`** — `.github/workflows/terraform.yml:27` | Blast: environment
  The `setup-terraform` action installs Terraform 1.9.x, but `versions.tf` requires `>= 1.10, < 1.15`. This means `terraform validate` in CI will fail with a version constraint error (or silently pass if `init -backend=false` skips the check).
  **Fix:** Change to `terraform_version: "~1.14"` to match local and constraint.

---

## 4. Robustness

### MEDIUM

- **[R-001] Root `variables.tf` lacks validation on `region`** — `terraform/variables.tf:3-7` | Blast: infrastructure-wide
  Both child modules validate `region` with a regex, but the root module variable has no validation. A typo at the root level would only be caught at apply time with a cryptic AWS error.
  **Fix:** Add the same validation block:
  ```hcl
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Must be a valid AWS region identifier (e.g. us-east-1)."
  }
  ```

- **[R-002] Neptune `deletion_protection` defaults differ between root and module** — `terraform/variables.tf:108-112`, `modules/terraform-graph-store/variables.tf:66-70` | Blast: module
  The root variable `neptune_deletion_protection` defaults to `false`, but the module variable `deletion_protection` defaults to `true`. Since the root passes the value explicitly, the root default wins — meaning production deployments using `task up` without overrides get `deletion_protection = false`.
  **Fix:** Change the root default to `true` at `terraform/variables.tf:112`.

---

## 5. Simplicity

### INFO

- **[X-001] `data.aws_caller_identity` in state-backend module** — `modules/state-backend/data.tf:1` | Blast: single-resource
  The state-backend module still uses its own `data.aws_caller_identity` call rather than receiving `account_id` as a variable. This is acceptable for a bootstrap module (it runs independently), but inconsistent with the pattern used by the other two modules.
  **Fix:** Optional — could pass `account_id` for consistency, but the bootstrap module is a separate root, so the current approach is fine.

---

## 6. Operational Readiness

### LOW

- **[O-001] No CloudWatch log retention policy** — `modules/hashicorp-docs-pipeline/main.tf:31-34`, `modules/terraform-graph-store/codebuild.tf:100-103` | Blast: module
  CodeBuild log groups are created by the `logs_config` block but no `aws_cloudwatch_log_group` resource with `retention_in_days` is defined. Logs will be retained indefinitely by default, accumulating cost.
  **Fix:** Add `aws_cloudwatch_log_group` resources with `retention_in_days = 90` (or similar) for both CodeBuild log groups.

---

## 7. CI/CD and Testing Maturity

### INFO

- **[C-001] No pre-commit framework** — repo root | Blast: environment
  No `.pre-commit-config.yaml`. The CI pipeline catches issues, but pre-commit hooks would catch them earlier.
  **Fix:** Add pre-commit with `terraform_fmt`, `terraform_validate`, `detect-secrets`, `shellcheck` hooks.

---

## 8. Cross-Module Contracts

No new findings. The root module uses `try()` for all conditional Neptune outputs (good). Type contracts match between root variables and module variables.

---

## 9. Stack-Specific Findings (AWS)

### MEDIUM

- **[K-001] CodeBuild egress in graph-store allows 0.0.0.0/0 on ports 80, 443, 8182** — `modules/terraform-graph-store/codebuild.tf:9-32` | Blast: module
  The CodeBuild security group allows unrestricted egress to three ports. Port 8182 egress to 0.0.0.0/0 is broader than needed — it only needs to reach the Neptune cluster.
  **Fix:** Scope the 8182 egress to the VPC CIDR or use `source_security_group_id` referencing the Neptune SG. Ports 80/443 to 0.0.0.0/0 are acceptable for GitHub clone and AWS API access.

---

## 10. CLAUDE.md Compliance

No `CLAUDE.md` found at repo root. The global `~/.claude/CLAUDE.md` applies. No Terraform-specific rules to verify.

---

## 11. Suppressed Findings

No `.tf-analyze-ignore.yaml` found. No inline suppressions.

---

## 12. Positive Findings

- **Clean module decomposition.** Three well-scoped modules (`hashicorp-docs-pipeline`, `terraform-graph-store`, `state-backend`) with consistent file layout (`iam.tf`, `s3.tf`, `variables.tf`, `outputs.tf`, `locals.tf`).
- **Provider `default_tags` usage.** `Project` and `ManagedBy` tags applied globally.
- **Remote S3 backend with native lock files.** `use_lockfile = true` — using the new Terraform-native locking (no DynamoDB needed).
- **Neptune gated behind `create_neptune` flag.** Prevents accidental deployment of expensive infrastructure.
- **Strong CI pipeline.** Terraform fmt + validate, Trivy security scan, ShellCheck, Python unit tests.
- **S3 bucket hardening across all modules.** Versioning, lifecycle rules, SSE, public access block on all 3 buckets.
- **`prevent_destroy` on all stateful resources.** Kendra index, RAG docs bucket, graph staging bucket, state bucket.
- **Input validation on dangerous variables.** Region, Kendra edition, VPC ID, subnet IDs, instance class, instance count, CodeBuild compute type all validated.
- **IAM least-privilege progress.** Service role policies (Kendra, CodeBuild, Step Functions, Scheduler) use specific resource ARNs. Only the GitHub Actions CI/CD role and EC2 networking use wildcards.
- **`account_id` passed as variable.** Eliminates duplicate `aws_caller_identity` calls in child modules.
- **Tags variable on all modules.** Resource-specific tagging is now possible.
- **Neptune audit logging enabled.** `neptune_enable_audit_log = 1` in cluster parameter group.

---

## 13. Recommended Action Plan

| Priority | Finding | Section | Effort | Blast Radius | Description |
|----------|---------|---------|--------|--------------|-------------|
| 1 | S-002 | Security | Small | infrastructure-wide | Commit `.terraform.lock.hcl` files to source control |
| 2 | Y-002 | Style | Small | environment | Fix CI Terraform version `~1.9` → `~1.14` |
| 3 | D-001 | DRY | Small | single-resource | Update stale `hashicorp-bedrock-ai-rag` repo name in tfvars files |
| 4 | S-001 | Security | Medium | infrastructure-wide | Scope GitHub Actions IAM `Resource` fields to specific ARNs/prefixes |
| 5 | R-002 | Robustness | Small | module | Change root `neptune_deletion_protection` default to `true` |
| 6 | R-001 | Robustness | Small | infrastructure-wide | Add region validation to root `variables.tf` |
| 7 | K-001 | AWS | Small | module | Scope CodeBuild SG port 8182 egress to VPC CIDR |
| 8 | S-003 | Security | Small | module | Add VPC condition to graph-store EC2 IAM |
| 9 | O-001 | Ops | Small | module | Add CloudWatch log group retention policies |
| 10 | C-001 | CI/CD | Small | environment | Add `.pre-commit-config.yaml` |

### Related Findings

- S-001 + S-003 + K-001: All relate to the graph-store module's security boundaries — address together
- S-002 + Y-002: Both are CI/CD supply-chain items — commit lock files and fix TF version in same PR
- D-001 + (repo rename): Quick text replacement, same PR
