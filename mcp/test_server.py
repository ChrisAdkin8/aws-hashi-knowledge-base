#!/usr/bin/env python3
"""test_server.py — Smoke-test the MCP server tool functions.

Runs tool functions directly (bypassing the MCP protocol) to confirm that
credentials, environment variables, and retrieval are working correctly.

Requires environment variables:
  AWS_REGION          — AWS region
  AWS_KENDRA_INDEX_ID — Kendra index ID

Usage:
    python3 mcp/test_server.py
"""

from __future__ import annotations

import logging
import os
import sys

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
log = logging.getLogger(__name__)


def _check_env() -> bool:
    missing = [v for v in ("AWS_REGION", "AWS_KENDRA_INDEX_ID") if not os.environ.get(v)]
    if missing:
        log.error("Missing environment variables: %s", ", ".join(missing))
        return False
    return True


def main() -> None:
    if not _check_env():
        sys.exit(1)

    from server import get_index_info, search_hashicorp_docs

    failures = 0

    # ── Test 1: get_index_info ────────────────────────────────────────────────
    log.info("Test 1: get_index_info")
    info = get_index_info()
    if "error" in info or "auth_error" in info or "index_error" in info:
        log.error("FAIL: %s", info)
        failures += 1
    else:
        log.info("PASS: region=%s index_id=%s status=%s",
                 info.get("region"), info.get("kendra_index_id"), info.get("index_status", "n/a"))

    # ── Test 2: basic search ──────────────────────────────────────────────────
    log.info("Test 2: search_hashicorp_docs (basic)")
    results = search_hashicorp_docs(query="How do I configure the AWS provider in Terraform?", top_k=3)
    if not results or "error" in results[0]:
        log.warning("WARN: Zero results for basic search (may indicate empty index)")
    else:
        log.info("PASS: %d results, top confidence=%s", len(results), results[0].get("confidence", "n/a"))

    # ── Test 3: filtered search ───────────────────────────────────────────────
    log.info("Test 3: search_hashicorp_docs (product_family=vault)")
    results = search_hashicorp_docs(query="dynamic secrets database Vault", top_k=5, product_family="vault")
    if not results or "error" in results[0]:
        log.warning("WARN: Zero results for vault filter (may indicate empty index)")
    else:
        wrong_family = [r for r in results if r.get("product_family") != "vault"]
        if wrong_family:
            log.error("FAIL: Results include non-vault product_family entries: %s", wrong_family)
            failures += 1
        else:
            log.info("PASS: %d results, all product_family=vault", len(results))

    # ── Test 4: no-results edge case ──────────────────────────────────────────
    log.info("Test 4: search_hashicorp_docs (nonsense query, high min_score)")
    results = search_hashicorp_docs(query="xyzzy frobnicator quux hashicorp", top_k=3, min_score=0.99)
    if results and "error" in results[0]:
        log.error("FAIL: Unexpected error on no-results query: %s", results)
        failures += 1
    else:
        log.info("PASS: %d results (expected 0 for nonsense+high threshold)", len(results))

    if failures > 0:
        log.error("%d test(s) failed", failures)
        sys.exit(1)
    else:
        log.info("All smoke tests passed.")


if __name__ == "__main__":
    main()
