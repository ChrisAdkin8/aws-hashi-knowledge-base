# MCP Server — HashiCorp RAG

The `mcp/server.py` server exposes the **Amazon Kendra** index as two tools callable from Claude Code via the [Model Context Protocol](https://modelcontextprotocol.io). Claude (running on Amazon Bedrock) calls these tools automatically when answering questions about HashiCorp products.

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

### `get_index_info`

Returns the active region, Kendra index ID, index edition, index status, and caller identity. Use for diagnostics.

---

## Setup

### 1. Install dependencies

```bash
task mcp:install
```

### 2. Register with Claude Code

```bash
task mcp:setup KENDRA_INDEX_ID=$(terraform -chdir=terraform output -raw kendra_index_id)
```

This writes to `.claude/settings.local.json`. Restart Claude Code to activate.

### 3. Smoke test

```bash
task mcp:test KENDRA_INDEX_ID=$(terraform -chdir=terraform output -raw kendra_index_id)
```

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
        "AWS_KENDRA_INDEX_ID": "<KENDRA_INDEX_ID>"
      }
    }
  }
}
```

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

## Authentication

The server uses the standard AWS credential chain — no additional configuration beyond what you use for `aws` CLI commands:

1. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables
2. `~/.aws/credentials` file
3. Instance profile (EC2/ECS/Lambda)
4. AWS SSO (`aws sso login --profile my-profile`)

The `AWS_REGION` and `AWS_KENDRA_INDEX_ID` env vars are written to the `mcpServers` entry by `task mcp:setup` and passed to the server process automatically.
