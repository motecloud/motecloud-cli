import os
import json
import hashlib
from datetime import datetime, timezone

def get_file_info(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
        return {
            "filename": os.path.basename(filepath),
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest()
        }

version = os.environ.get("CLI_VERSION", "v0.2.0")
product = "motecloud-cli"
base_dir = f"dist/{product}/{version}"
bundle_path = f"dist/{product}/{product}-{version}.tar.gz"

artifacts = []
for filename in os.listdir(base_dir):
    if filename != "SHA256SUMS":
        artifacts.append(get_file_info(os.path.join(base_dir, filename)))

bundle_info = get_file_info(bundle_path)
bundle_info["path"] = bundle_path

manifest = {
    "schema_version": 1,
    "product": product,
    "version": version,
    "generated_utc": datetime.now(timezone.utc).isoformat(),
    "artifacts": artifacts,
    "bundle": bundle_info
}

manifest_path = os.path.join(base_dir, "RELEASE_MANIFEST.json")
with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2)

print(f"Created {manifest_path}")
print(f"Manifest SHA256: {get_file_info(manifest_path)['sha256']}")
