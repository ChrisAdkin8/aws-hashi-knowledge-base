#!/usr/bin/env python3
"""server.py — MCP server exposing the Kendra index as Claude Code tools.

Tools:
  - search_hashicorp_docs — keyword/semantic search with optional metadata filters
  - get_index_info        — inspect active region/index configuration

Environment variables:
  AWS_REGION          — AWS region (defaults to boto3 session region, then us-east-1)
  AWS_KENDRA_INDEX_ID — Kendra index ID (required)
  Standard AWS credential chain (env vars, ~/.aws/credentials, instance profile, SSO)
"""

from __future__ import annotations

import logging
import os
from typing import Any

import boto3
from mcp.server.fastmcp import FastMCP

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
log = logging.getLogger(__name__)

mcp = FastMCP("hashicorp-rag")

AWS_REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name or "us-east-1"
KENDRA_INDEX_ID = os.environ.get("AWS_KENDRA_INDEX_ID", "")

# Kendra confidence levels mapped to numeric equivalents for min_score filtering
CONFIDENCE_SCORE: dict[str, float] = {
    "VERY_HIGH":     1.00,
    "HIGH":          0.75,
    "MEDIUM":        0.50,
    "LOW":           0.25,
    "NOT_AVAILABLE": 0.00,
}


def _kendra_client() -> Any:
    return boto3.client("kendra", region_name=AWS_REGION)


@mcp.tool()
def search_hashicorp_docs(
    query: str,
    top_k: int = 5,
    min_score: float = 0.0,
    product_family: str = "",
    source_type: str = "",
) -> list[dict]:
    """Search the HashiCorp documentation Kendra index.

    Performs a keyword + semantic search against the Kendra index containing
    HashiCorp documentation, provider references, GitHub issues, Discuss forum
    threads, and blog posts.

    Args:
        query:          Natural-language search query.
        top_k:          Maximum number of results to return (default 5).
        min_score:      Minimum confidence score 0-1 (VERY_HIGH=1.0, HIGH=0.75,
                        MEDIUM=0.5, LOW=0.25). Default 0.0 returns all results.
        product_family: Optional filter — terraform, vault, consul, nomad, packer,
                        boundary, sentinel.
        source_type:    Optional filter — documentation, provider, module, issue,
                        discuss, blog.

    Returns:
        List of result dicts with keys: text, score, confidence, source_uri,
        product, product_family, source_type.
    """
    if not KENDRA_INDEX_ID:
        return [{"error": "AWS_KENDRA_INDEX_ID environment variable is not set."}]

    client = _kendra_client()

    params: dict = {
        "IndexId":              KENDRA_INDEX_ID,
        "QueryText":            query,
        "PageSize":             top_k * 2 if (product_family or source_type) else top_k,
        "QueryResultTypeFilter": "DOCUMENT",
    }

    # Push metadata filters down to Kendra for efficiency
    filters = []
    if product_family:
        filters.append({
            "EqualsTo": {"Key": "product_family", "Value": {"StringValue": product_family}}
        })
    if source_type:
        filters.append({
            "EqualsTo": {"Key": "source_type", "Value": {"StringValue": source_type}}
        })
    if len(filters) == 1:
        params["AttributeFilter"] = filters[0]
    elif len(filters) > 1:
        params["AttributeFilter"] = {"AndAllFilters": filters}

    try:
        resp = client.query(**params)
    except Exception as exc:
        log.error("Kendra query error: %s", exc)
        return [{"error": str(exc)}]

    output: list[dict] = []
    for item in resp.get("ResultItems", []):
        confidence = item.get("ScoreAttributes", {}).get("ScoreConfidence", "NOT_AVAILABLE")
        score = CONFIDENCE_SCORE.get(confidence, 0.0)
        if score < min_score:
            continue

        text = item.get("DocumentExcerpt", {}).get("Text", "")
        doc_uri = item.get("DocumentURI", item.get("DocumentId", ""))

        # Kendra returns custom attributes directly — no path inference needed
        attrs = {
            a["Key"]: a["Value"].get("StringValue", "")
            for a in item.get("DocumentAttributes", [])
            if "StringValue" in a.get("Value", {})
        }

        output.append({
            "text":           text,
            "score":          score,
            "confidence":     confidence,
            "source_uri":     doc_uri,
            "product":        attrs.get("product", "hashicorp"),
            "product_family": attrs.get("product_family", "hashicorp"),
            "source_type":    attrs.get("source_type", ""),
        })

        if len(output) >= top_k:
            break

    return output


@mcp.tool()
def get_index_info() -> dict:
    """Return the active Kendra index configuration.

    Returns:
        Dict with region, kendra_index_id, index status, and caller identity.
    """
    info: dict = {
        "region":           AWS_REGION,
        "kendra_index_id":  KENDRA_INDEX_ID or "(not set — AWS_KENDRA_INDEX_ID missing)",
    }

    try:
        sts = boto3.client("sts", region_name=AWS_REGION)
        identity = sts.get_caller_identity()
        info["aws_account_id"] = identity.get("Account", "unknown")
        info["aws_arn"] = identity.get("Arn", "unknown")
    except Exception as exc:
        info["auth_error"] = str(exc)

    if KENDRA_INDEX_ID:
        try:
            kendra = boto3.client("kendra", region_name=AWS_REGION)
            resp = kendra.describe_index(Id=KENDRA_INDEX_ID)
            info["index_name"]   = resp.get("Name", "")
            info["index_status"] = resp.get("Status", "")
            info["edition"]      = resp.get("Edition", "")
        except Exception as exc:
            info["index_error"] = str(exc)

    return info


if __name__ == "__main__":
    mcp.run()
