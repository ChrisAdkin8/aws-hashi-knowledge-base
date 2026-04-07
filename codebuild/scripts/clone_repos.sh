#!/usr/bin/env bash
# clone_repos.sh — Shallow-clone HashiCorp GitHub repos for documentation ingestion.
# Core repos (vault, consul, nomad, terraform, etc.) are required: any clone failure
# aborts the build. Provider and Sentinel repos are optional: failures are warned
# and skipped.
set -euo pipefail

REPOS_DIR="/codebuild/output/repos"
mkdir -p "${REPOS_DIR}"

declare -A CORE_REPOS=(
  # web-unified-docs is the authoritative source for Vault, Consul, Nomad,
  # Terraform Enterprise, and HCP Terraform documentation. The individual
  # product repos (hashicorp/vault etc.) have deprecated their website/ trees.
  ["web-unified-docs"]="https://github.com/hashicorp/web-unified-docs.git"
  ["terraform"]="https://github.com/hashicorp/terraform.git"
  ["packer"]="https://github.com/hashicorp/packer.git"
  ["boundary"]="https://github.com/hashicorp/boundary.git"
  ["waypoint"]="https://github.com/hashicorp/waypoint.git"
  ["terraform-docs-agents"]="https://github.com/hashicorp/terraform-docs-agents.git"
  ["terraform-website"]="https://github.com/hashicorp/terraform-website.git"
)

declare -A PROVIDER_REPOS=(
  ["terraform-provider-aws"]="https://github.com/hashicorp/terraform-provider-aws.git"
  ["terraform-provider-azurerm"]="https://github.com/hashicorp/terraform-provider-azurerm.git"
  ["terraform-provider-google"]="https://github.com/hashicorp/terraform-provider-google.git"
  ["terraform-provider-kubernetes"]="https://github.com/hashicorp/terraform-provider-kubernetes.git"
  ["terraform-provider-helm"]="https://github.com/hashicorp/terraform-provider-helm.git"
  ["terraform-provider-docker"]="https://github.com/kreuzwerker/terraform-provider-docker.git"
  ["terraform-provider-vault"]="https://github.com/hashicorp/terraform-provider-vault.git"
  ["terraform-provider-consul"]="https://github.com/hashicorp/terraform-provider-consul.git"
  ["terraform-provider-nomad"]="https://github.com/hashicorp/terraform-provider-nomad.git"
  ["terraform-provider-random"]="https://github.com/hashicorp/terraform-provider-random.git"
  ["terraform-provider-null"]="https://github.com/hashicorp/terraform-provider-null.git"
  ["terraform-provider-local"]="https://github.com/hashicorp/terraform-provider-local.git"
  ["terraform-provider-tls"]="https://github.com/hashicorp/terraform-provider-tls.git"
  ["terraform-provider-http"]="https://github.com/hashicorp/terraform-provider-http.git"
)

declare -A SENTINEL_REPOS=(
  ["sentinel-policies"]="https://github.com/hashicorp/sentinel-policies.git"
  ["terraform-sentinel-policies"]="https://github.com/hashicorp/terraform-sentinel-policies.git"
  ["vault-sentinel-policies"]="https://github.com/hashicorp/vault-sentinel-policies.git"
  ["consul-sentinel-policies"]="https://github.com/hashicorp/consul-sentinel-policies.git"
)

clone_repo_optional() {
  local name="$1"
  local url="$2"
  local dest="${REPOS_DIR}/${name}"
  if [[ -d "${dest}/.git" ]]; then
    echo "Skipping ${name} — already cloned"
    return 0
  fi
  echo "Cloning optional repo ${name}..."
  git clone --depth 1 --single-branch "${url}" "${dest}" 2>&1 || {
    echo "WARN: Failed to clone ${name} from ${url} — skipping"
  }
}

# ─── Phase 1: Core repos (required — build fails if any clone fails) ───────────
echo "==> Phase 1: Cloning core repos (required)"
core_pids=()

for name in "${!CORE_REPOS[@]}"; do
  dest="${REPOS_DIR}/${name}"
  if [[ -d "${dest}/.git" ]]; then
    echo "Skipping ${name} — already cloned"
    continue
  fi
  echo "Cloning ${name}..."
  git clone --depth 1 --single-branch "${CORE_REPOS[$name]}" "${dest}" 2>&1 &
  core_pids+=($!)
done

core_failed=0
for pid in "${core_pids[@]}"; do
  if ! wait "${pid}"; then
    core_failed=$((core_failed + 1))
  fi
done

if [[ "${core_failed}" -gt 0 ]]; then
  echo "ERROR: ${core_failed} core repo clone(s) failed — aborting build"
  exit 1
fi
echo "Core repos cloned successfully."

# ─── Phase 2: Optional repos (provider + sentinel — failures are non-fatal) ───
echo ""
echo "==> Phase 2: Cloning optional repos (provider + sentinel)"
opt_pids=()

for name in "${!PROVIDER_REPOS[@]}"; do
  clone_repo_optional "${name}" "${PROVIDER_REPOS[$name]}" &
  opt_pids+=($!)
done

for name in "${!SENTINEL_REPOS[@]}"; do
  clone_repo_optional "${name}" "${SENTINEL_REPOS[$name]}" &
  opt_pids+=($!)
done

opt_failed=0
for pid in "${opt_pids[@]}"; do
  if ! wait "${pid}"; then
    opt_failed=$((opt_failed + 1))
  fi
done

if [[ "${opt_failed}" -gt 0 ]]; then
  echo "WARN: ${opt_failed} optional repo clone(s) failed — continuing with available repos"
fi

echo ""
echo "==> Clone phase complete. Repositories are in: ${REPOS_DIR}"
