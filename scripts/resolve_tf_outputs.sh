#!/usr/bin/env bash
# resolve_tf_outputs.sh — Resolve common Terraform outputs as shell exports.
#
# Respects pre-set env vars (for CLI overrides). Falls back to terraform output.
# Usage: eval "$(scripts/resolve_tf_outputs.sh terraform)"
set -euo pipefail

TF_DIR="${1:-terraform}"

resolve() {
  local var="$1" output="$2" default="${3:-}"
  local current="${!var:-}"
  if [ -n "$current" ]; then
    echo "$current"
  else
    terraform -chdir="$TF_DIR" output -raw "$output" 2>/dev/null || echo "$default"
  fi
}

cat <<EOF
export KENDRA_INDEX_ID="$(resolve KENDRA_INDEX_ID kendra_index_id)"
export KENDRA_DS_ID="$(resolve KENDRA_DS_ID kendra_data_source_id)"
export STATE_MACHINE_ARN="$(resolve STATE_MACHINE_ARN state_machine_arn)"
export RAG_BUCKET="$(resolve RAG_BUCKET rag_bucket_name)"
export NEPTUNE_ENDPOINT="$(resolve NEPTUNE_ENDPOINT neptune_cluster_endpoint)"
export NEPTUNE_PORT="$(resolve NEPTUNE_PORT neptune_port 8182)"
export NEPTUNE_PROXY_URL="$(resolve NEPTUNE_PROXY_URL neptune_proxy_url)"
export GRAPH_STATE_MACHINE_ARN="$(resolve GRAPH_STATE_MACHINE_ARN graph_state_machine_arn)"
export GRAPH_STAGING_BUCKET="$(resolve GRAPH_STAGING_BUCKET graph_staging_bucket_name)"
EOF
