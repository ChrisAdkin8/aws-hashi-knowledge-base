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

import boto3

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
        # Kendra uses 'DocumentExcerpt' for general snippets 
        # and 'AdditionalAttributes' for specific types.
        excerpt = item.get("DocumentExcerpt", {}).get("Text", "")
        if excerpt:
            chunks.append(excerpt)
            
    if not chunks:
        log.warning(f"No results found for query: {query}")
        
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

    client = boto3.client("kendra", region_name=args.region)
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
    overall_saving = int((1 - total_rag / total_raw) * 100) if total_raw > 0 else 0
    print(f"{'Total':<60} {total_rag:>6} {total_raw:>8} {overall_saving:>7}%")
    print(f"\nAverage RAG tokens/query: {total_rag // len(TEST_QUERIES)}")
    print(f"Average raw tokens/query: {total_raw // len(TEST_QUERIES)}")
    print(f"Overall token saving:      {overall_saving}%")


if __name__ == "__main__":
    main()
