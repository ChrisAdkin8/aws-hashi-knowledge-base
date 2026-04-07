#!/usr/bin/env python3
"""test_token_efficiency.py — Compare RAG token cost vs raw documentation.

Runs cross-product queries against the Kendra index and estimates the token
savings compared to pasting full documentation pages.

Usage:
    python3 scripts/test_token_efficiency.py \\
        --region us-east-1 \\
        --kendra-index-id ABCDEFGHIJ \\
        [--top-k 5]
"""

from __future__ import annotations

import argparse
import logging
import sys

import boto3
from botocore.exceptions import ClientError, EndpointResolutionError, NoRegionError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
log = logging.getLogger(__name__)

# Estimated raw documentation token counts (full pages, conservative)
TEST_QUERIES: list[dict] = [
    {"query": "How do I configure an S3 backend in Terraform?",                        "raw_tokens": 9500},
    {"query": "How do I set up the AWS provider in Terraform?",                        "raw_tokens": 11000},
    {"query": "How do I generate dynamic secrets with HashiCorp Vault?",               "raw_tokens": 14000},
    {"query": "How do I configure Consul service mesh with mTLS?",                     "raw_tokens": 16000},
    {"query": "How do I build a Packer AMI with an HCL template?",                    "raw_tokens": 8500},
    {"query": "How do I use Vault dynamic secrets with the Terraform AWS provider?",   "raw_tokens": 22000},
    {"query": "How do I schedule a Docker workload in Nomad?",                         "raw_tokens": 12000},
    {"query": "How do I enforce Sentinel policies in Terraform Cloud?",                "raw_tokens": 13500},
    {"query": "How do I compose reusable Terraform modules?",                          "raw_tokens": 10000},
    {"query": "How do I integrate Consul service discovery with Vault?",               "raw_tokens": 19500},
]


def _count_tokens(text: str) -> int:
    try:
        import tiktoken
        enc = tiktoken.get_encoding("cl100k_base")
        return len(enc.encode(text))
    except ImportError:
        return int(len(text.split()) * 1.3)


KENDRA_SUPPORTED_REGIONS = [
    "us-east-1", "us-east-2", "us-west-2",
    "eu-west-1", "eu-west-2",
    "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2",
    "ca-central-1",
]


def validate_index(client: object, index_id: str, region: str) -> None:
    """Verify the index exists and is ACTIVE; raise with actionable message if not."""
    try:
        resp = client.describe_index(Id=index_id)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code == "ResourceNotFoundException":
            # Try to find the index in supported regions to give a better hint
            hint = _find_index_region(index_id, exclude=region)
            msg = f"Index '{index_id}' not found in region '{region}'."
            if hint:
                msg += f" Found it in '{hint}' — rerun with --region {hint}"
            else:
                msg += " Check the index ID and region."
            log.error(msg)
            sys.exit(1)
        if code in ("AccessDeniedException", "UnauthorizedException"):
            log.error("Permission denied accessing index '%s' in '%s'. Check IAM.", index_id, region)
            sys.exit(1)
        raise
    except EndpointResolutionError:
        supported = ", ".join(KENDRA_SUPPORTED_REGIONS)
        log.error(
            "Kendra endpoint not available in region '%s'. "
            "Supported regions: %s",
            region, supported,
        )
        sys.exit(1)

    status = resp.get("Status", "UNKNOWN")
    if status != "ACTIVE":
        log.error("Index '%s' is not ACTIVE (status=%s). Wait until it is ready.", index_id, status)
        sys.exit(1)

    log.info("Index '%s' is ACTIVE in '%s'.", index_id, region)


def _find_index_region(index_id: str, exclude: str) -> str | None:
    """Search supported Kendra regions for the given index ID. Returns region or None."""
    for region in KENDRA_SUPPORTED_REGIONS:
        if region == exclude:
            continue
        try:
            c = boto3.client("kendra", region_name=region)
            c.describe_index(Id=index_id)
            return region
        except Exception:
            pass
    return None


def retrieve(client: object, index_id: str, query: str, top_k: int) -> str:
    """Query Kendra and return concatenated excerpt text."""
    resp = client.query(
        IndexId=index_id,
        QueryText=query,
        PageSize=top_k,
        # Removing QueryResultTypeFilter allows Kendra to return the best
        # matches regardless of whether it classifies them as DOCUMENT or ANSWER.
    )

    chunks = []
    for item in resp.get("ResultItems", []):
        excerpt = item.get("DocumentExcerpt", {}).get("Text", "")
        if excerpt:
            chunks.append(excerpt)

    if not chunks:
        log.warning("No results found for query: %s", query)

    return "\n\n---\n\n".join(chunks)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", required=True)
    parser.add_argument("--kendra-index-id", required=True)
    parser.add_argument("--top-k", type=int, default=5)
    args = parser.parse_args()

    try:
        import tiktoken  # noqa: F401
        token_method = "tiktoken (cl100k_base)"
    except ImportError:
        token_method = "word-count approximation (install tiktoken for exact counts)"

    log.info("Token counting: %s", token_method)

    if args.region not in KENDRA_SUPPORTED_REGIONS:
        supported = ", ".join(KENDRA_SUPPORTED_REGIONS)
        log.error(
            "Region '%s' does not support Kendra. Supported regions: %s",
            args.region, supported,
        )
        sys.exit(1)

    client = boto3.client("kendra", region_name=args.region)
    validate_index(client, args.kendra_index_id, args.region)
    total_rag = 0
    total_raw = 0

    print(f"\n{'Query':<60} {'RAG':>6} {'Raw':>8} {'Saving':>8}")
    print("-" * 85)

    for test in TEST_QUERIES:
        query = test["query"]
        raw_tokens = test["raw_tokens"]
        try:
            context = retrieve(client, args.kendra_index_id, query, args.top_k)
            rag_tokens = _count_tokens(context)
        except Exception as exc:
            log.error("Retrieval failed for '%s': %s", query[:40], exc)
            continue

        saving_pct = int((1 - rag_tokens / raw_tokens) * 100) if raw_tokens > 0 else 0
        short_query = query[:58] + ".." if len(query) > 60 else query
        print(f"{short_query:<60} {rag_tokens:>6} {raw_tokens:>8} {saving_pct:>7}%")
        total_rag += rag_tokens
        total_raw += raw_tokens

    print("-" * 85)
    if total_raw == 0:
        log.error("No queries returned results. Check that the index has been populated.")
        sys.exit(1)
    overall_saving = int((1 - total_rag / total_raw) * 100)
    n = len(TEST_QUERIES)
    print(f"{'Total':<60} {total_rag:>6} {total_raw:>8} {overall_saving:>7}%")
    print(f"\nAverage RAG tokens/query: {total_rag // n}")
    print(f"Average raw tokens/query: {total_raw // n}")
    print(f"Overall token saving:      {overall_saving}%")


if __name__ == "__main__":
    main()
