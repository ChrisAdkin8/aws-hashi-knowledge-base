#!/usr/bin/env python3
"""generate_metadata.py — Fixed Kendra-compatible metadata generator."""

import argparse
import json
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
log = logging.getLogger(__name__)

INPUT_DIR = Path("/codebuild/output/cleaned")

SOURCE_TYPE_MAP: dict[str, str] = {
    "documentation": "documentation",
    "provider": "provider",
    "module": "module",
    "sentinel": "sentinel",
    "issues": "issue",
    "discuss": "discuss",
    "blogs": "blog",
}

PRODUCT_FAMILY_OVERRIDES: dict[str, str] = {
    "provider": "terraform",
    "module": "terraform",
    "sentinel": "terraform",
}

def _infer_metadata(path: Path, bucket: str) -> dict:
    """Infer metadata fields with corrected schema for Kendra."""
    rel = path.relative_to(INPUT_DIR)
    parts = rel.parts

    raw_source_type = parts[0] if parts else "documentation"
    source_type = SOURCE_TYPE_MAP.get(raw_source_type, raw_source_type)

    product = "hashicorp"
    if source_type == "provider" and len(parts) >= 2:
        product = parts[1].removeprefix("terraform-provider-")
    elif source_type == "documentation" and len(parts) >= 2:
        product = parts[1]
    elif source_type == "issue" and len(parts) >= 3:
        product = parts[2]
    elif source_type == "discuss" and len(parts) >= 2:
        product = parts[1]
    elif source_type == "blog" and len(parts) >= 2:
        product = parts[1]

    product_family = PRODUCT_FAMILY_OVERRIDES.get(source_type, product)

    # Use forward slashes for S3 URI regardless of OS
    s3_key = "/".join(rel.parts)
    title = path.stem.replace("_", " ").title()

    # Schema Fix: Reserved system attributes like _source_uri MUST be 
    # nested inside the Attributes object, alongside custom attributes.
    return {
        "Title": title,
        "ContentType": "PLAIN_TEXT",
        "Attributes": {
            "_source_uri": f"s3://{bucket}/{s3_key}",
            "product": product or "unknown",
            "product_family": product_family or "unknown",
            "source_type": source_type or "unknown"
        }
    }

def write_sidecar(path: Path, metadata: dict) -> None:
    """Writes the metadata file using the exact required naming convention."""
    # FIX: Append .metadata.json to the FULL filename (e.g. doc.md.metadata.json)
    # Using path.name ensures we don't lose the .md extension.
    sidecar_path = path.parent / (path.name + ".metadata.json")
    
    # FIX: Write clean JSON without trailing newlines or BOM
    with open(sidecar_path, 'w', encoding='utf-8') as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    args = parser.parse_args()

    bucket = args.bucket.removeprefix("s3://").strip("/")
    
    if not INPUT_DIR.exists():
        log.error("Input directory %s does not exist", INPUT_DIR)
        return

    md_files = list(INPUT_DIR.rglob("*.md"))
    written = 0

    for path in md_files:
        try:
            metadata = _infer_metadata(path, bucket)
            write_sidecar(path, metadata)
            written += 1
        except Exception as e:
            log.error("Failed to process %s: %s", path, e)

    log.info("Complete — %d sidecar files written", written)

if __name__ == "__main__":
    main()