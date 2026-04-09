#!/usr/bin/env bash
# test_graph.sh — Validate Neptune graph has nodes and edges via the API Gateway proxy.
#
# Called by `task graph:test`.
set -euo pipefail

PROXY_URL=""

usage() { echo "Usage: $0 --proxy-url URL"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxy-url) PROXY_URL="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[[ -z "${PROXY_URL}" ]] && { echo "Error: --proxy-url required"; exit 1; }

neptune_query() {
  curl -sf -X POST "${PROXY_URL}/query" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$1\"}"
}

echo "Neptune proxy: ${PROXY_URL}"
echo ""

echo "── Node count by label ──────────────────────────────────"
NODE_RESULT=$(neptune_query "MATCH (n) RETURN labels(n) AS label, count(n) AS count ORDER BY count DESC")
echo "${NODE_RESULT}" | jq -r '.results[]? | "\(.label): \(.count)"' 2>/dev/null || echo "${NODE_RESULT}"
TOTAL_NODES=$(echo "${NODE_RESULT}" | jq '[.results[]?.count // 0] | add // 0' 2>/dev/null || echo "?")

echo ""
echo "── Edge count by type ───────────────────────────────────"
EDGE_RESULT=$(neptune_query "MATCH ()-[r]->() RETURN type(r) AS type, count(r) AS count ORDER BY count DESC")
echo "${EDGE_RESULT}" | jq -r '.results[]? | "\(.type): \(.count)"' 2>/dev/null || echo "${EDGE_RESULT}"
TOTAL_EDGES=$(echo "${EDGE_RESULT}" | jq '[.results[]?.count // 0] | add // 0' 2>/dev/null || echo "?")

echo ""
echo "── Summary ──────────────────────────────────────────────"
echo "  Total nodes: ${TOTAL_NODES}"
echo "  Total edges: ${TOTAL_EDGES}"

if [[ "${TOTAL_NODES}" == "0" ]] || [[ "${TOTAL_NODES}" == "?" ]]; then
  echo ""
  echo "WARN: Graph is empty. Run 'task graph:populate' first."
  exit 1
fi

echo ""
echo "OK: Neptune graph populated."
