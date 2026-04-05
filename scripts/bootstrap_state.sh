#!/usr/bin/env bash
# bootstrap_state.sh — Create S3 state bucket (one-time setup).
# State locking uses native S3 lock files (use_lockfile = true); no DynamoDB table needed.
#
# Usage:
#   scripts/bootstrap_state.sh --region us-west-2
#   scripts/bootstrap_state.sh --region us-east-1  # Note: us-east-1 omits LocationConstraint
#
# The bucket name is deterministic:
#   Bucket: <ACCOUNT_ID>-tf-state-<8-char hash>
set -euo pipefail

REGION="us-west-2"

usage() {
  echo "Usage: $0 [--region REGION]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${ACCOUNT_ID}-tf-state-$(echo -n "${ACCOUNT_ID}" | sha256sum | cut -c1-8)"

echo "Account ID:   ${ACCOUNT_ID}"
echo "State bucket: ${BUCKET_NAME}"
echo "Region:       ${REGION}"
echo ""

# ── S3 state bucket ────────────────────────────────────────────────────────────

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "OK: State bucket already exists — ${BUCKET_NAME}"
else
  echo "Creating state bucket ${BUCKET_NAME}..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi

  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'

  aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

  echo "OK: Created state bucket ${BUCKET_NAME}"
fi

echo ""
echo "Bootstrap complete."
echo "Use the following backend-config flags with terraform init:"
echo "  -backend-config=\"bucket=${BUCKET_NAME}\""
echo "  -backend-config=\"region=${REGION}\""
