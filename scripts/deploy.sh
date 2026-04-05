#!/usr/bin/env bash
# deploy.sh — End-to-end deploy orchestrator for the HashiCorp Bedrock RAG pipeline (Kendra backend).
#
# Called by `task up`. Idempotent — safe to re-run.
#
# Steps:
#   1. Bootstrap S3 state bucket
#   2. terraform init + terraform apply (provisions all infra including Kendra index + data source)
#   3. Trigger first pipeline run (unless --skip-pipeline)
#
# Usage:
#   scripts/deploy.sh --region us-west-2 --repo-uri https://github.com/org/repo
set -euo pipefail

REGION="us-east-1"
REPO_URI=""
SKIP_PIPELINE=false
TF_DIR="terraform"

usage() {
  echo "Usage: $0 --region REGION --repo-uri REPO_URI [--skip-pipeline]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)        REGION="$2";        shift 2 ;;
    --repo-uri)      REPO_URI="$2";      shift 2 ;;
    --skip-pipeline) SKIP_PIPELINE=true; shift 1 ;;
    -h|--help)       usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

if [[ -z "${REPO_URI}" ]]; then
  echo "ERROR: --repo-uri is required"
  usage
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="${ACCOUNT_ID}-tf-state-$(echo -n "${ACCOUNT_ID}" | sha256sum | cut -c1-8)"

echo "==> Step 1: Bootstrap state bucket"
bash scripts/bootstrap_state.sh --region "${REGION}"

echo ""
echo "==> Step 2: terraform init + apply"
export AWS_DEFAULT_REGION="${REGION}"

# Detect actual bucket region (may differ from deployment region if bucket pre-exists)
BUCKET_REGION=$(aws s3api get-bucket-location --bucket "${STATE_BUCKET}" --query LocationConstraint --output text 2>/dev/null || echo "${REGION}")
if [[ "${BUCKET_REGION}" == "None" ]] || [[ -z "${BUCKET_REGION}" ]]; then
  BUCKET_REGION="us-east-1"
fi
echo "State bucket region: ${BUCKET_REGION} (deploy region: ${REGION})"

terraform -chdir="${TF_DIR}" init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${BUCKET_REGION}" \
  -reconfigure \
  -input=false

# Write tfvars if not already present
if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
  cat > "${TF_DIR}/terraform.tfvars" <<EOF
region   = "${REGION}"
repo_uri = "${REPO_URI}"
EOF
  echo "Wrote ${TF_DIR}/terraform.tfvars"
fi

echo ""
echo "==> Step 2a: Import OIDC provider if it already exists in AWS"
OIDC_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[].Arn" --output text 2>/dev/null \
  | tr '\t' '\n' | grep "token.actions.githubusercontent.com" || true)
if [[ -z "${OIDC_ARN}" ]]; then
  echo "OIDC: provider not found in AWS — will be created by terraform apply."
elif terraform -chdir="${TF_DIR}" state show 'aws_iam_openid_connect_provider.github[0]' &>/dev/null; then
  echo "OIDC: already in Terraform state — nothing to do."
else
  echo "OIDC: importing existing provider ${OIDC_ARN} into Terraform state..."
  terraform -chdir="${TF_DIR}" import 'aws_iam_openid_connect_provider.github[0]' "${OIDC_ARN}"
  echo "OIDC: import complete."
fi

# NOTE: Kendra index creation takes 10-30 minutes — Terraform waits automatically.
echo ""
echo "Note: Kendra index provisioning takes 10-30 minutes — Terraform will wait."
terraform -chdir="${TF_DIR}" apply -auto-approve -input=false

echo ""
if [[ "${SKIP_PIPELINE}" == "true" ]]; then
  echo "Skipping pipeline run (--skip-pipeline set)."
else
  echo "==> Step 3: Trigger first pipeline run"
  STATE_MACHINE_ARN=$(terraform -chdir="${TF_DIR}" output -raw state_machine_arn)
  KENDRA_INDEX_ID=$(terraform -chdir="${TF_DIR}" output -raw kendra_index_id)
  KENDRA_DS_ID=$(terraform -chdir="${TF_DIR}" output -raw kendra_data_source_id)
  RAG_BUCKET=$(terraform -chdir="${TF_DIR}" output -raw rag_bucket_name)

  bash scripts/run_pipeline.sh \
    --state-machine-arn   "${STATE_MACHINE_ARN}" \
    --region              "${REGION}" \
    --kendra-index-id     "${KENDRA_INDEX_ID}" \
    --kendra-data-source-id "${KENDRA_DS_ID}" \
    --bucket-name         "${RAG_BUCKET}" \
    --repo-url            "${REPO_URI}" \
    --wait
fi

echo ""
echo "Deploy complete."
KENDRA_INDEX_ID=$(terraform -chdir="${TF_DIR}" output -raw kendra_index_id)
echo "Kendra Index ID: ${KENDRA_INDEX_ID}"
echo ""
echo "Validate retrieval:"
echo "  task pipeline:test KENDRA_INDEX_ID=${KENDRA_INDEX_ID}"
echo ""
echo "Set up MCP server for Claude Code:"
echo "  task mcp:setup KENDRA_INDEX_ID=${KENDRA_INDEX_ID}"
