#!/usr/bin/env bash
# clone_repos_and_extract_docs.sh — Shallow-clone HashiCorp GitHub repos and extract docs.
# Outputs clean documentation to /codebuild/output/docs_to_sync/.
set -euo pipefail

REPOS_DIR="/codebuild/output/repos"
DOCS_DIR="/codebuild/output/docs_to_sync"

mkdir -p "${REPOS_DIR}"
mkdir -p "${DOCS_DIR}"

declare -A CORE_REPOS=(
  ["terraform"]="https://github.com/hashicorp/terraform.git"
  ["vault"]="https://github.com/hashicorp/vault.git"
  ["consul"]="https://github.com/hashicorp/consul.git"
  ["nomad"]="https://github.com/hashicorp/nomad.git"
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

clone_repo() {
  local name="$1"
  local url="$2"
  local dest="${REPOS_DIR}/${name}"

  if [[ -d "${dest}/.git" ]]; then
    echo "Skipping ${name} — already cloned"
    return 0
  fi

  echo "Cloning ${name}..."
  git clone --depth 1 --single-branch "${url}" "${dest}" 2>&1 || {
    echo "WARN: Failed to clone ${name} from ${url} — skipping"
  }
}

export -f clone_repo
export REPOS_DIR

echo "==> Phase 1: Parallel Cloning"
pids=()

for name in "${!CORE_REPOS[@]}"; do
  clone_repo "${name}" "${CORE_REPOS[$name]}" &
  pids+=($!)
done

for name in "${!PROVIDER_REPOS[@]}"; do
  clone_repo "${name}" "${PROVIDER_REPOS[$name]}" &
  pids+=($!)
done

for name in "${!SENTINEL_REPOS[@]}"; do
  clone_repo "${name}" "${SENTINEL_REPOS[$name]}" &
  pids+=($!)
done

# Wait for all parallel clones to complete
failed=0
for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
    failed=$((failed + 1))
  fi
done

if [[ "${failed}" -gt 0 ]]; then
  echo "WARN: ${failed} clone(s) failed — check output above. Continuing with available repos."
fi
echo "Clone phase complete."

echo ""
echo "==> Phase 2: Extracting Markdown Documentation"
# This step pulls only .md and .mdx files, preserving the directory structure
# so files with the same name (like README.md) don't overwrite each other.

for repo_path in "${REPOS_DIR}"/*; do
  if [[ -d "${repo_path}" ]]; then
    repo_name=$(basename "${repo_path}")
    target_dir="${DOCS_DIR}/${repo_name}"
    
    mkdir -p "${target_dir}"
    
    # Use find and copy to grab only the markdown files and ignore Go source code
    # The 'cp --parents' flag ensures we keep the folder structure intact.
    # Note: Using subshell (cd ...) so paths remain relative inside the target dir.
    (
      cd "${repo_path}"
      find . -type f \( -name "*.md" -o -name "*.mdx" \) -exec cp --parents {} "${target_dir}/" \; 2>/dev/null || true
    )
    
    # Count how many docs we extracted for logging
    doc_count=$(find "${target_dir}" -type f | wc -l)
    echo "Extracted ${doc_count} documentation files from ${repo_name}"
  fi
done

echo ""
echo "==> Done!"
echo "Raw repositories are in: ${REPOS_DIR}"
echo "Clean documentation ready for S3/Kendra is in: ${DOCS_DIR}"

# Optional: Uncomment the next line if you want to free up space in CodeBuild by deleting the raw Go code
# rm -rf "${REPOS_DIR}"