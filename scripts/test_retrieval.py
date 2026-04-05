#!/usr/bin/env python3
"""test_retrieval.py — Validate Kendra retrieval quality.

Runs a suite of test queries across all product families and source types.

Usage:
    python3 scripts/test_retrieval.py \\
        --region us-east-1 \\
        --kendra-index-id ABCDEFGHIJ \\
        [--min-confidence MEDIUM] \\
        [--top-k 5]
"""

from __future__ import annotations

import argparse
import logging
import sys

import boto3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
log = logging.getLogger(__name__)

# Kendra confidence levels in descending order
CONFIDENCE_LEVELS = ["VERY_HIGH", "HIGH", "MEDIUM", "LOW", "NOT_AVAILABLE"]
CONFIDENCE_SCORE = {"VERY_HIGH": 1.0, "HIGH": 0.75, "MEDIUM": 0.5, "LOW": 0.25, "NOT_AVAILABLE": 0.0}

TEST_QUERIES: list[dict] = [
    {"topic": "terraform-provider", "query": "How do I configure the AWS provider in Terraform?"},
    {"topic": "vault",              "query": "How do I generate dynamic database credentials using HashiCorp Vault?"},
    {"topic": "consul",             "query": "How do I set up mTLS between services using Consul Connect?"},
    {"topic": "nomad",              "query": "How do I define a Nomad job specification for a Docker container?"},
    {"topic": "sentinel",           "query": "How do I write a Sentinel policy to restrict resource creation in Terraform?"},
    {"topic": "packer",             "query": "How do I build an AMI with Packer using an HCL template?"},
    {"topic": "terraform-module",   "query": "What is the structure of a reusable Terraform module?"},
    {"topic": "github-issue",       "query": "What are common issues when upgrading the Terraform AWS provider?"},
    {"topic": "discuss-thread",     "query": "How do I troubleshoot Terraform state locking errors?"},
    {"topic": "blog-post",          "query": "What new features were announced for HashiCorp products?"},
]


def run_query(client: object, index_id: str, query: str, top_k: int, min_confidence: str) -> tuple[int, str | None]:
    """Run a single Kendra query. Returns (qualified_count, top_confidence)."""
    resp = client.query(
        IndexId=index_id,
        QueryText=query,
        PageSize=top_k,
        QueryResultTypeFilter="DOCUMENT",
    )
    items = resp.get("ResultItems", [])
    if not items:
        return 0, None

    top_confidence = items[0].get("ScoreAttributes", {}).get("ScoreConfidence", "NOT_AVAILABLE")
    min_rank = CONFIDENCE_LEVELS.index(min_confidence)
    qualified = [
        item for item in items
        if CONFIDENCE_LEVELS.index(item.get("ScoreAttributes", {}).get("ScoreConfidence", "NOT_AVAILABLE")) <= min_rank
    ]
    return len(qualified), top_confidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", required=True)
    parser.add_argument("--kendra-index-id", required=True)
    parser.add_argument("--min-confidence", default="LOW",
                        choices=CONFIDENCE_LEVELS, help="Minimum Kendra confidence level")
    parser.add_argument("--top-k", type=int, default=5)
    args = parser.parse_args()

    client = boto3.client("kendra", region_name=args.region)
    failed: list[str] = []

    print(f"\n{'Topic':<25} {'Results':>8} {'Top Confidence':>16} {'Status':>8}")
    print("-" * 65)

    for test in TEST_QUERIES:
        topic = test["topic"]
        try:
            count, top_conf = run_query(client, args.kendra_index_id, test["query"], args.top_k, args.min_confidence)
        except Exception as exc:
            log.error("Query failed for %s: %s", topic, exc)
            failed.append(topic)
            continue

        status = "PASS" if count > 0 else "WARN"
        conf_str = top_conf if top_conf else "n/a"
        print(f"{topic:<25} {count:>8} {conf_str:>16} {status:>8}")
        if count == 0:
            log.warning("Zero results for topic '%s' — index may have coverage gaps", topic)

    print("-" * 65)

    if failed:
        print(f"\nFAIL: {len(failed)} queries errored: {', '.join(failed)}")
        sys.exit(1)
    else:
        print("\nAll queries completed — check WARN lines for coverage gaps.")


if __name__ == "__main__":
    main()
