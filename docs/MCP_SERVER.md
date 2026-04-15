# HashiCorp RAG — MCP Server

The MCP server (`mcp/server.py`) exposes the Amazon Kendra index and Amazon
Neptune graph database as tools that any MCP-compatible client can call — most
usefully Claude Code, which gains the ability to look up HashiCorp documentation
and traverse Terraform dependency graphs automatically during a conversation
without any manual copy-paste.

---

## Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Registering with Claude Code](#registering-with-claude-code)
- [Tool Reference](#tool-reference)
  - [search\_hashicorp\_docs](#search_hashicorp_docs)
  - [get\_resource\_dependencies](#get_resource_dependencies)
  - [find\_resources\_by\_type](#find_resources_by_type)
  - [get\_index\_info](#get_index_info)
- [Testing](#testing)
- [Manual Usage (without Claude Code)](#manual-usage-without-claude-code)
- [Troubleshooting](#troubleshooting)

---

## Overview

```
Claude Code
    |
    |  MCP (stdio transport)
    v
mcp/server.py
    |
    +---> Amazon Kendra
    |         |
    |         |  keyword + semantic search
    |         v
    |     HashiCorp documentation index
    |     (Terraform providers, Vault, Consul, Nomad,
    |      Packer, Sentinel, GitHub issues, Discourse,
    |      blog posts)
    |
    +---> Amazon Neptune (openCypher)
              |
              |  graph traversal
              v
          Terraform resource dependency graph
          (:Repository, :Resource nodes;
           [:CONTAINS], [:DEPENDS_ON] edges)
```

When Claude Code needs information about a HashiCorp product, it calls
`search_hashicorp_docs` with a natural language query. The server queries the
Kendra index and returns the most relevant document chunks. When Claude needs to
understand infrastructure topology, it calls `get_resource_dependencies` or
`find_resources_by_type` to traverse the Neptune graph. Claude then uses those
results — with full source attribution — to answer the question.

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Python | >= 3.11 | provided by `.venv` |
| boto3 | >= 1.34.0 | AWS SDK for Kendra and Neptune |
| requests | >= 2.31.0 | HTTP client for Neptune openCypher endpoint |
| mcp | >= 1.3.0 | Model Context Protocol Python SDK |
| AWS credentials | — | Standard credential chain (`aws configure` or SSO) |
| Kendra index | deployed | created by `task apply` |
| Neptune cluster | deployed | opt-in via `create_graph_store = true` |

The virtual environment (`.venv`) is created by the existing preflight tasks
and already contains `boto3` and `requests`. Only the `mcp` package needs to
be added.

---

## Installation

```bash
# 1. Install the mcp package into the existing venv
task mcp:install

# 2. Verify the installation
.venv/bin/python3 -c "import mcp; import boto3; print('OK')"
```

---

## Configuration

The server reads the following environment variables. `AWS_REGION` and
`AWS_KENDRA_INDEX_ID` are required for Kendra tools; Neptune variables are
optional and enable graph tools when set.

| Variable | Required | Default | Description |
|---|---|---|---|
| `AWS_REGION` | yes | `us-east-1` | AWS region for Kendra and Neptune. |
| `AWS_KENDRA_INDEX_ID` | yes | — | Kendra index ID. |
| `NEPTUNE_PROXY_URL` | no | — | API Gateway URL for Neptune proxy (recommended for outside VPC). |
| `NEPTUNE_ENDPOINT` | no | — | Neptune cluster writer endpoint (direct VPC access). |
| `NEPTUNE_PORT` | no | `8182` | Neptune port (direct access only). |
| `NEPTUNE_IAM_AUTH` | no | `"true"` | Enable SigV4 auth for Neptune (direct access only). |

When `NEPTUNE_PROXY_URL` is set, it takes precedence over `NEPTUNE_ENDPOINT`.
The proxy route signs requests for the `execute-api` service instead of
`neptune-db`.

Authentication is handled entirely through the standard AWS credential chain.
No additional configuration beyond what you use for `aws` CLI commands:

1. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables
2. `~/.aws/credentials` file
3. Instance profile (EC2/ECS/Lambda)
4. AWS SSO (`aws sso login --profile my-profile`)

Neptune SigV4 auth uses `botocore.auth.SigV4Auth` with service name
`neptune-db` (direct access) or `execute-api` (proxy access). Fresh credentials
are obtained on each query to handle temporary credential expiry in the
long-running MCP server process.

---

## Registering with Claude Code

The setup task writes the server entry into `.claude/settings.local.json` so
that Claude Code starts the MCP server automatically when it opens this project.

```bash
# Auto-detect Kendra index ID and Neptune endpoint from Terraform output
task mcp:setup
```

After the task completes, **restart Claude Code**. The tools
`search_hashicorp_docs`, `get_resource_dependencies`, `find_resources_by_type`,
and `get_index_info` will appear in the tool list immediately.

### What the task writes

`task mcp:setup` adds the following block to `.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "hashicorp-rag": {
      "command": "/abs/path/to/.venv/bin/python3",
      "args": ["/abs/path/to/mcp/server.py"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_KENDRA_INDEX_ID": "<index-id>",
        "NEPTUNE_PROXY_URL": "https://<api-id>.execute-api.<region>.amazonaws.com/query"
      }
    }
  }
}
```

The absolute paths are resolved at setup time so the server works regardless
of the working directory from which Claude Code is launched.

### Updating after an index refresh

If you create a new Kendra index (e.g. after `task apply`), re-run:

```bash
task mcp:setup
```

Then restart Claude Code.

---

## Tool Reference

### search\_hashicorp\_docs

Search the HashiCorp documentation index for relevant results using Kendra
keyword and semantic search.

**Input schema**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `query` | string | yes | — | Natural language question or topic. |
| `top_k` | integer | no | `5` | Number of results to return. Range: 1-20. |
| `min_score` | float | no | `0.0` | Minimum confidence score. Range: 0.0-1.0. |
| `product_family` | string | no | — | Filter by product family (see below). |
| `source_type` | string | no | — | Filter by document source type (see below). |

**min\_score values**

| Value | Kendra confidence |
|---|---|
| `1.00` | VERY_HIGH |
| `0.75` | HIGH |
| `0.50` | MEDIUM |
| `0.25` | LOW |
| `0.00` | NOT_AVAILABLE (accept all) |

**product\_family values**

| Value | Covers |
|---|---|
| `terraform` | All Terraform providers, modules, Terraform CLI docs |
| `vault` | Vault docs, secrets engines, auth methods |
| `consul` | Consul service mesh, health checks, KV |
| `nomad` | Nomad job specs, schedulers, drivers |
| `packer` | Packer templates, builders, provisioners |
| `boundary` | Boundary targets, auth methods, sessions |
| `sentinel` | HashiCorp Sentinel policy framework |

**source\_type values**

| Value | Description |
|---|---|
| `documentation` | Core product docs (Vault, Consul, Nomad, etc.) |
| `provider` | Terraform provider documentation |
| `module` | Terraform Registry module READMEs |
| `issue` | GitHub issue threads |
| `discuss` | HashiCorp Discuss forum threads |
| `blog` | HashiCorp blog posts |

**How Kendra metadata filtering works**

Kendra indexes custom attributes from the `.metadata.json` sidecar files
alongside each document. The `search_hashicorp_docs` tool pushes filters down
to Kendra at query time using `AttributeFilter`:

```python
# Single filter
params["AttributeFilter"] = {
    "EqualsTo": {"Key": "product_family", "Value": {"StringValue": "vault"}}
}

# Combined filters
params["AttributeFilter"] = {
    "AndAllFilters": [
        {"EqualsTo": {"Key": "product_family", "Value": {"StringValue": "terraform"}}},
        {"EqualsTo": {"Key": "source_type",    "Value": {"StringValue": "provider"}}},
    ]
}
```

This is more efficient than post-filtering: Kendra scores and ranks only within
the matching document set.

**Output format**

Each result is a dict with `text`, `score`, `confidence`, `source_uri`,
`product`, `product_family`, `source_type`. Kendra returns custom metadata
attributes directly from the `.metadata.json` sidecar files written during
ingestion — no path inference needed.

**Example calls**

```
# Basic search
search_hashicorp_docs("How do I configure the AWS Terraform provider?")

# Increase breadth (more results)
search_hashicorp_docs("Vault dynamic secrets", top_k=10)

# Filter to Vault documentation only
search_hashicorp_docs("Enable PKI secrets engine", product_family="vault", source_type="documentation")

# Filter to GitHub issues about Consul
search_hashicorp_docs("Consul service discovery failing", product_family="consul", source_type="issue")

# High-confidence results only
search_hashicorp_docs("S3 bucket policy", min_score=0.75)
```

---

### get\_resource\_dependencies

Traverse the Terraform resource dependency graph in Neptune. Finds resources
that a given resource depends on (downstream), resources that depend on it
(upstream), or both.

**Input schema**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `resource_type` | string | yes | — | Terraform resource type (e.g. `aws_lambda_function`). |
| `resource_name` | string | yes | — | Terraform resource name (e.g. `processor`). |
| `direction` | string | no | `"both"` | `"downstream"` (what this depends on), `"upstream"` (what depends on this), or `"both"`. |
| `max_depth` | integer | no | `2` | Maximum traversal depth. Range: 1-5. |

**How Neptune graph queries work**

The graph tools query Neptune via openCypher HTTP POST with SigV4-signed
requests. The graph contains:

- **`:Repository`** nodes — GitHub repos (properties: `uri`, `name`)
- **`:Resource`** nodes — Terraform resources (properties: `id`, `repo`, `type`, `name`)
- **`[:CONTAINS]`** edges — Repository -> Resource
- **`[:DEPENDS_ON]`** edges — Resource -> Resource

Dependency traversal uses variable-length path patterns (`[:DEPENDS_ON*1..N]`)
to walk the graph up to the specified depth.

**Output format**

List of dicts with `resource_id`, `type`, `name`, `direction`, `repository`.

**Example calls**

```
# Find all dependencies of an IAM role (both directions)
get_resource_dependencies("aws_iam_role", "lambda_exec")

# Only downstream (what this resource depends on)
get_resource_dependencies("aws_lambda_function", "processor", direction="downstream")

# Deep traversal (up to 5 hops)
get_resource_dependencies("aws_s3_bucket", "data", direction="both", max_depth=5)
```

---

### find\_resources\_by\_type

List all Terraform resources of a given type from the Neptune graph.

**Input schema**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `resource_type` | string | yes | — | Terraform resource type (e.g. `aws_s3_bucket`, `aws_iam_role`). |
| `repository` | string | no | — | Filter by repository (GitHub HTTPS URL or repo name). |

**Output format**

List of dicts with `resource_id`, `type`, `name`, `repository`.

**Example calls**

```
# All S3 buckets across all repos
find_resources_by_type("aws_s3_bucket")

# IAM roles in a specific repo
find_resources_by_type("aws_iam_role", repository="my-org/my-repo")
```

---

### get\_index\_info

Return configuration and status details for diagnostics. Takes no arguments.

**Output example**

```
{
  "region": "us-east-1",
  "kendra_index_id": "a1b2c3d4-...",
  "index_edition": "ENTERPRISE_EDITION",
  "index_status": "ACTIVE",
  "caller_identity": "arn:aws:iam::123456789012:user/dev",
  "neptune_endpoint": "my-cluster.cluster-abc.us-east-1.neptune.amazonaws.com",
  "neptune_port": 8182,
  "neptune_iam_auth": true,
  "neptune_status": "ok",
  "neptune_node_counts": {"Repository": 5, "Resource": 142}
}
```

When Neptune is not configured, the `neptune_*` fields are omitted and only
Kendra diagnostics are returned.

---

## Testing

Run the smoke-test suite against the live index:

```bash
task mcp:test
```

This executes `mcp/test_server.py` which runs up to six checks:

| # | Check | Validates |
|---|---|---|
| 1 | `get_index_info` | Environment variables are set; index is ACTIVE; caller identity is correct |
| 2 | `search_hashicorp_docs` — basic query | Kendra retrieval returns at least one result |
| 3 | `search_hashicorp_docs` — filtered query | Metadata filtering (product_family=vault) is exercised |
| 4 | `search_hashicorp_docs` — no-results query | Edge case returns zero results with high min_score |
| 5 | `find_resources_by_type` | Neptune query returns resources (Neptune only) |
| 6 | `get_resource_dependencies` | Neptune dependency traversal works (Neptune only) |

Neptune tests (5-6) run automatically when `NEPTUNE_ENDPOINT` or
`NEPTUNE_PROXY_URL` is available; otherwise they are skipped.

Expected output for a healthy deployment:

```
Test 1: get_index_info
PASS: region=us-east-1 index_id=a1b2c3d4-... status=ACTIVE neptune=ok

Test 2: search_hashicorp_docs (basic)
PASS: 3 results, top confidence=HIGH

Test 3: search_hashicorp_docs (product_family=vault)
PASS: 5 results, all product_family=vault

Test 4: search_hashicorp_docs (nonsense query, high min_score)
PASS: 0 results (expected 0 for nonsense+high threshold)

Test 5: find_resources_by_type (aws_iam_role)
PASS: 12 resources found (0 is ok if graph is empty)

Test 6: get_resource_dependencies (aws_iam_role, test, both)
PASS: 3 dependencies found (0 is ok if resource doesn't exist)

All smoke tests passed.
```

---

## Manual Usage (without Claude Code)

You can query the index from any terminal using the MCP inspector or by calling
the Python functions directly.

### Direct Python call

```bash
AWS_REGION=us-east-1 \
AWS_KENDRA_INDEX_ID=a1b2c3d4-5678-90ab-cdef-example \
NEPTUNE_PROXY_URL=https://abc123.execute-api.us-east-1.amazonaws.com/query \
.venv/bin/python3 - <<'EOF'
import importlib.util, pathlib

spec = importlib.util.spec_from_file_location("rag_server", "mcp/server.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

print(mod.get_index_info())
print()
print(mod.search_hashicorp_docs(
    "How do I configure the AWS Terraform provider?",
    top_k=3,
    product_family="terraform",
))
print()
print(mod.find_resources_by_type("aws_s3_bucket"))
EOF
```

### MCP Inspector (interactive)

```bash
AWS_REGION=us-east-1 \
AWS_KENDRA_INDEX_ID=a1b2c3d4-5678-90ab-cdef-example \
NEPTUNE_PROXY_URL=https://abc123.execute-api.us-east-1.amazonaws.com/query \
npx @modelcontextprotocol/inspector .venv/bin/python3 mcp/server.py
```

The inspector opens a local web UI where you can call tools interactively and
inspect the JSON responses. Requires Node.js.

---

## Troubleshooting

### `AWS_KENDRA_INDEX_ID is not set`

The server started but the environment variables were not injected. Check the
`env` block in `.claude/settings.local.json` and ensure the values match your
deployment. Re-run `task mcp:setup` if in doubt.

### `AccessDeniedException` from Kendra

AWS credentials are not configured or do not have `kendra:Query` permission.
Verify your credentials:

```bash
aws sts get-caller-identity
aws kendra describe-index --id <index-id> --region <region>
```

### `ResourceNotFoundException` from Kendra

The index ID in `AWS_KENDRA_INDEX_ID` does not match an index in the configured
region. Confirm the correct ID:

```bash
task output  # shows kendra_index_id from Terraform
```

### Neptune connection refused or timeout

Neptune does not expose a public endpoint. For access from outside the VPC:

1. Deploy the Neptune proxy (`neptune_create_proxy = true` in Terraform).
2. Set `NEPTUNE_PROXY_URL` to the API Gateway endpoint (from
   `terraform output neptune_proxy_url`).
3. Ensure your IAM identity has `execute-api:Invoke` on the API Gateway route.

For direct access, the MCP server must reach the cluster on port 8182 — via SSH
tunnel, AWS Client VPN, or by running from within the VPC.

### Server does not appear in Claude Code

1. Confirm `.claude/settings.local.json` contains the `mcpServers.hashicorp-rag`
   block (run `task mcp:setup` to write it).
2. Restart Claude Code completely (quit and reopen, not just a new session).
3. Check the MCP server log in the Claude Code developer console for startup
   errors.

### `mcp` package not found

The `mcp` PyPI package is not installed in `.venv`. Run:

```bash
task mcp:install
```

### Filtered search returns fewer results than expected

Kendra scores and ranks only within the matching document set when
`AttributeFilter` is applied. If the index contains few documents matching the
filter combination, the result count will be low. Options:

- Lower `min_score` to 0.0 to accept all confidence levels.
- Remove one of the filters (e.g. drop `source_type` and keep only
  `product_family`).
- Run `task pipeline:run` to re-ingest the index with updated documents.
