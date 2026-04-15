# AGENTS.md - Universal AI Operational Guide

This repository provisions a high-precision Amazon Kendra RAG pipeline plus an
opt-in Neptune Graph for Terraform dependency analysis, both surfaced through
a unified MCP server, for the HashiCorp ecosystem (Terraform, Vault, Consul,
Nomad, Packer, Boundary).

---

## Quick Commands

| Category | Command |
| :--- | :--- |
| **Deploy** | `task up REPO_URI={url}` - REGION auto-detected from `terraform.tfvars` |
| **Docs pipeline (full)** | `task docs:run` |
| **Docs pipeline (targeted)** | `task docs:run TARGET=blogs` - `all`, `docs`, `registry`, `discuss`, `blogs` |
| **Docs status** | `task docs:status` |
| **Docs validation** | `task docs:test` |
| **Token efficiency** | `task test:token-efficiency` |
| **Graph populate** | `task graph:populate GRAPH_REPO_URIS="https://github.com/org/repo"` |
| **Graph status** | `task graph:status` |
| **Graph validate** | `task graph:test` |
| **MCP setup** | `task mcp:setup` (auto-detects IDs from Terraform output) |
| **Claude Bedrock** | `task claude:setup` (routes Claude Code through Bedrock) |
| **Terraform** | `task plan` \| `task apply` (plan-then-apply) \| `task validate` \| `task destroy` |
| **CI** | `task ci` (parallel: fmt:check, validate, shellcheck, tests) |

---

## Architectural Pillars

* **Single-apply deployment**: All infrastructure - IAM, S3, Kendra, CodeBuild,
  Step Functions, EventBridge - is provisioned in a single `terraform apply`.
  No two-step bootstrapping required.
* **Step Functions orchestration**: The state machine uses `.sync` integration
  for CodeBuild (no polling loop - Step Functions uses CloudWatch Events to
  detect build completion). Kendra sync uses a manual poll loop
  (`WaitForSync` -> `ListSyncJobs` -> `CheckSyncStatus`) because
  `kendra:startDataSourceSyncJob` has no `.sync` integration.
* **Semantic Pre-splitting**: `process_docs.py` splits docs at `##`/`###`
  heading boundaries before upload. Sections under 200 chars are merged into
  the previous section; sections over ~4,000 chars are split at code-fence
  boundaries. Kendra then applies its own NLP-powered passage extraction - no
  chunking configuration required.
* **Metadata Engine**: `generate_metadata.py` produces `.metadata.json` sidecar
  files next to every document. These are uploaded to S3 alongside the markdown
  and read by Kendra at sync time. Attributes (`product`, `product_family`,
  `source_type`) are indexed for faceted filtering in the MCP server.
* **Cross-Source Deduplication**: `deduplicate.py` removes near-duplicate files
  by SHA-256 of normalised body content before upload. Prevents the same content
  entering through multiple sources.
* **Sequential Validation**: The `ValidateRetrieval` state uses a Step Functions
  `Map` state with `MaxConcurrency: 1` to run test queries covering all product
  families sequentially. Sequential execution avoids Kendra query throttling.
  Zero results log a warning but do NOT fail the pipeline.
* **Targeted Pipeline Runs**: The `PIPELINE_TARGET` environment variable (set in
  Step Functions input and passed to CodeBuild) controls which content sources
  are ingested. Each CodeBuild phase gates its steps on this variable, enabling
  partial re-ingestion without a full rebuild.

---

## Project State & Resources

| Resource | Value / Path |
| :--- | :--- |
| **Region** | Auto-detected from `terraform/terraform.tfvars` (default `us-east-1`) |
| **State bucket** | S3, created by `terraform/bootstrap/` |
| **Kendra index** | Provisioned by `terraform/modules/hashicorp-docs-pipeline/` |
| **Kendra data source** | S3-backed, `inclusion_patterns = ["**/*.md"]` |
| **Neptune cluster** | Only when `create_neptune = true` in `terraform.tfvars` |
| **Neptune proxy** | API Gateway + Lambda (opt-in: `neptune_create_proxy = true`) |
| **Step Functions (docs)** | `step-functions/rag_pipeline.asl.json` |
| **Step Functions (graph)** | `step-functions/graph_pipeline.asl.json` |
| **CodeBuild (docs)** | `codebuild/buildspec.yml` - PIPELINE_TARGET gating |
| **CodeBuild (graph)** | `codebuild/buildspec_graph.yml` |
| **MCP server** | `mcp/server.py` |

---

## Critical Constraints

* **Region**: Kendra is not available in all regions. Supported: `us-east-1`,
  `us-east-2`, `us-west-2`, `eu-west-1`, `eu-west-2`, `ap-southeast-1`,
  `ap-southeast-2`, `ap-northeast-1`, `ap-northeast-2`, `ca-central-1`.
  Bedrock Claude models require `us-west-2` or `us-east-1` for broadest
  availability.
* **Kendra edition**: Cannot be changed in-place. Changing `kendra_edition`
  (DEVELOPER -> ENTERPRISE or vice versa) destroys and recreates the index.
  Re-run `task docs:run` after to re-sync all documents.
* **DEVELOPER_EDITION document limit**: Capped at 10,000 docs. This pipeline
  typically generates 10,000-30,000+ documents. Use `ENTERPRISE_EDITION` for
  production.
* **Bedrock model access**: Must be explicitly enabled per region in the Bedrock
  console (Model access -> Request access). Used at query time only - not during
  ingestion.
* **Neptune is opt-in**: Set `create_neptune = true` in `terraform.tfvars` and
  supply `neptune_vpc_id` and `neptune_subnet_ids`. Without this,
  `task graph:populate` will fail with `graph_state_machine_arn not found`.
* **S3 data source configuration**: Use `s3_configuration` with
  `inclusion_patterns = ["**/*.md"]`. Do not use `exclusion_patterns` - it
  blocks `.metadata.json` sidecars. Do not use `template_configuration` - it is
  invalid for S3 type.

---

## Maintenance Workflow

1. **Modify logic**: Update this file or `CLAUDE.md` to refine standards.
2. **Apply infra**: `task apply` plans then applies Terraform changes.
3. **Sync knowledge**: `task docs:run` re-ingests docs (or `task docs:run
   TARGET=blogs` for targeted); `task graph:populate` re-ingests the dependency
   graph.
4. **Validate**: `task docs:test && task graph:test && task test:token-efficiency`.
