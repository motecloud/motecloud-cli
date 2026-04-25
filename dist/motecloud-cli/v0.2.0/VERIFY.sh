#!/bin/bash
set -e
echo "Verifying local artifacts..."
sha256sum -c SHA256SUMS
echo "Verifying bundle..."
BUNDLE_SHA256=$(cat ../motecloud-cli-v0.2.0.tar.gz.sha256)
echo "$BUNDLE_SHA256  ../motecloud-cli-v0.2.0.tar.gz" | sha256sum -c -
echo "Verification successful."
