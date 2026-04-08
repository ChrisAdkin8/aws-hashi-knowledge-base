# MCP Server — HashiCorp RAG + Graph

The `mcp/server.py` server exposes the **Amazon Kendra** index and **Amazon Neptune** graph database as tools callable from Claude Code via the [Model Context Protocol](https://modelcontextprotocol.io). Claude calls these tools automatically when answering questions about HashiCorp products or Terraform infrastructure topology.

## Tools

### `search_hashicorp_docs`

Performs a keyword + semantic search against the Kendra index.

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `query` | string | (required) | Natural-language search query |
| `top_k` | int | `5` | Maximum results to return |
| `min_score` | float | `0.0` | Minimum confidence score (VERY_HIGH=1.0, HIGH=0.75, MEDIUM=0.5, LOW=0.25) |
| `product_family` | string | `""` | Filter: `terraform`, `vault`, `consul`, `nomad`, `packer`, `boundary`, `sentinel` |
| `source_type` | string | `""` | Filter: `documentation`, `provider`, `module`, `issue`, `discuss`, `blog` |

**Returns:** List of result dicts with `text`, `score`, `confidence`, `source_uri`, `product`, `product_family`, `source_type`.

Kendra returns custom metadata attributes (`product`, `product_family`, `source_type`) directly from the `.metadata.json` sidecar files written during ingestion — no path inference needed.

### `get_resource_dependencies`

Traverses the Terraform resource dependency graph in Neptune. Finds resources that a given resource depends on (downstream), resources that depend on it (upstream), or both.

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `resource_type` | string | (required) | Terraform resource type (e.g. `aws_lambda_function`) |
| `resource_name` | string | (required) | Terraform resource name (e.g. `processor`) |
| `direction` | string | `"both"` | `"downstream"` (what this depends on), `"upstream"` (what depends on this), or `"both"` |
| `max_depth` | int | `2` | Maximum traversal depth (1-5) |

**Returns:** List of dicts with `resource_id`, `type`, `name`, `direction`, `repository`.

### `find_resources_by_type`

Lists all Terraform resources of a given type from the Neptune graph.

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `resource_type` | string | (required) | Terraform resource type (e.g. `aws_s3_bucket`, `aws_iam_role`) |
| `repository` | string | `""` | Optional — filter by repository (GitHub HTTPS URL or repo name) |

**Returns:** List of dicts with `resource_id`, `type`, `name`, `repository`.

### `get_index_info`

Returns the active region, Kendra index ID, index edition, index status, Neptune connectivity, node counts, and caller identity. Use for diagnostics.

When Neptune is configured, the response includes `neptune_endpoint`, `neptune_port`, `neptune_iam_auth`, `neptune_status`, and `neptune_node_counts`.

---

## Setup

### 1. Install dependencies

```bash
task mcp:install
```

### 2. Register with Claude Code

```bash
task mcp:setup
```

KENDRA_INDEX_ID and NEPTUNE_ENDPOINT are auto-detected from Terraform output. This writes to `.claude/settings.local.json`. Restart Claude Code to activate.

### 3. Smoke test

```bash
task mcp:test
```

Neptune tests run automatically when `NEPTUNE_ENDPOINT` is available.

---

## Manual configuration

If you prefer to configure the MCP server manually, add this to `.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "hashicorp-rag": {
      "command": ".venv/bin/python3",
      "args": ["/path/to/mcp/server.py"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_KENDRA_INDEX_ID": "<KENDRA_INDEX_ID>",
        "NEPTUNE_PROXY_URL": "https://<API_ID>.execute-api.<REGION>.amazonaws.com/query"
      }
    }
  }
}
```

**Access modes for Neptune:**

- **Via proxy (recommended for outside VPC):** Set `NEPTUNE_PROXY_URL` to the API Gateway endpoint (from `terraform output neptune_proxy_url`). Requires `neptune_create_proxy = true` in Terraform. The MCP server signs requests with SigV4 for the `execute-api` service.
- **Direct (from within VPC):** Set `NEPTUNE_ENDPOINT` and optionally `NEPTUNE_PORT` / `NEPTUNE_IAM_AUTH`. Used when running from EC2/ECS/CodeBuild inside the VPC.

Omit all `NEPTUNE_*` variables if Neptune is not deployed — the Kendra tools will still work.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AWS_REGION` | Yes | `us-east-1` | AWS region for Kendra and Neptune |
| `AWS_KENDRA_INDEX_ID` | Yes (for Kendra tools) | — | Kendra index ID |
| `NEPTUNE_PROXY_URL` | No (for graph tools) | — | API Gateway URL for Neptune proxy (recommended for outside VPC) |
| `NEPTUNE_ENDPOINT` | No (for graph tools) | — | Neptune cluster writer endpoint (direct VPC access) |
| `NEPTUNE_PORT` | No | `8182` | Neptune port (direct access only) |
| `NEPTUNE_IAM_AUTH` | No | `"true"` | Enable SigV4 auth for Neptune (direct access only) |

When `NEPTUNE_PROXY_URL` is set, it takes precedence over `NEPTUNE_ENDPOINT`. The proxy route signs requests for the `execute-api` service instead of `neptune-db`.

---

## How Kendra metadata filtering works

Kendra indexes custom attributes from the `.metadata.json` sidecar files alongside each document. The `search_hashicorp_docs` tool pushes filters down to Kendra at query time:

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

This is more efficient than post-filtering: Kendra scores and ranks only within the matching document set.

---

## How Neptune graph queries work

The graph tools query Neptune via openCypher HTTP POST with SigV4-signed requests. The graph contains:

- **`:Repository`** nodes — GitHub repos (properties: `uri`, `name`)
- **`:Resource`** nodes — Terraform resources (properties: `id`, `repo`, `type`, `name`)
- **`[:CONTAINS]`** edges — Repository → Resource
- **`[:DEPENDS_ON]`** edges — Resource → Resource

Dependency traversal uses variable-length path patterns (`[:DEPENDS_ON*1..N]`) to walk the graph up to the specified depth.

> **VPC connectivity:** Neptune does not expose a public endpoint. For access from outside the VPC, deploy the Neptune proxy (`neptune_create_proxy = true`) and set `NEPTUNE_PROXY_URL`. For direct access, the MCP server must reach the cluster on port 8182 — via SSH tunnel, AWS Client VPN, or by running from within the VPC.

---

## Authentication

The server uses the standard AWS credential chain — no additional configuration beyond what you use for `aws` CLI commands:

1. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables
2. `~/.aws/credentials` file
3. Instance profile (EC2/ECS/Lambda)
4. AWS SSO (`aws sso login --profile my-profile`)

Neptune SigV4 auth uses `botocore.auth.SigV4Auth` with service name `neptune-db` (direct access) or `execute-api` (proxy access). Fresh credentials are obtained on each query to handle temporary credential expiry in the long-running MCP server process.

When using the proxy, the caller's IAM identity needs `execute-api:Invoke` on the API Gateway route.

The environment variables are written to the `mcpServers` entry by `task mcp:setup` and passed to the server process automatically.
