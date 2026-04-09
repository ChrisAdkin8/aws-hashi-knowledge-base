#!/usr/bin/env bash
# run_graph_pipeline.sh — Start the graph extraction Step Functions pipeline and wait.
#
# Called by `task graph:populate` and `scripts/deploy.sh`.
set -euo pipefail

REGION=""
GRAPH_STATE_MACHINE_ARN=""
NEPTUNE_ENDPOINT=""
NEPTUNE_PORT="8182"
GRAPH_STAGING_BUCKET=""
REPO_URIS_RAW=""

usage() {
  echo "Usage: $0 --region R --state-machine-arn ARN --neptune-endpoint EP --graph-staging-bucket B --repo-uris 'url1 url2'"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)                REGION="$2";                shift 2 ;;
    --state-machine-arn)     GRAPH_STATE_MACHINE_ARN="$2"; shift 2 ;;
    --neptune-endpoint)      NEPTUNE_ENDPOINT="$2";      shift 2 ;;
    --neptune-port)          NEPTUNE_PORT="$2";          shift 2 ;;
    --graph-staging-bucket)  GRAPH_STAGING_BUCKET="$2";  shift 2 ;;
    --repo-uris)             REPO_URIS_RAW="$2";         shift 2 ;;
    -h|--help)               usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[[ -z "${GRAPH_STATE_MACHINE_ARN}" ]] && { echo "Error: --state-machine-arn required"; exit 1; }
[[ -z "${REPO_URIS_RAW}" ]]          && { echo "Error: --repo-uris required"; exit 1; }
[[ -z "${REGION}" ]]                  && { echo "Error: --region required"; exit 1; }

REPO_JSON=$(echo "${REPO_URIS_RAW}" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s .)
INPUT=$(jq -n \
  --argjson repo_uris "${REPO_JSON}" \
  --arg bucket "${GRAPH_STAGING_BUCKET}" \
  --arg endpoint "${NEPTUNE_ENDPOINT}" \
  --arg port "${NEPTUNE_PORT}" \
  --arg region "${REGION}" \
  '{repo_uris: $repo_uris, graph_staging_bucket: $bucket, neptune_endpoint: $endpoint, neptune_port: $port, region: $region}')

echo "Starting graph pipeline..."
echo "Repos: $(echo "${REPO_JSON}" | jq -r '.[]')"

EXECUTION_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "${GRAPH_STATE_MACHINE_ARN}" \
  --input "${INPUT}" --region "${REGION}" \
  --query executionArn --output text)
echo "Execution: ${EXECUTION_ARN}"
echo "Polling for completion..."

while true; do
  STATUS=$(aws stepfunctions describe-execution \
    --execution-arn "${EXECUTION_ARN}" --region "${REGION}" \
    --query status --output text)
  echo "  Status: ${STATUS}"
  case "${STATUS}" in
    SUCCEEDED) echo "Graph pipeline complete."; break ;;
    FAILED|TIMED_OUT|ABORTED) echo "Graph pipeline ${STATUS}."; exit 1 ;;
    *) sleep 30 ;;
  esac
done
