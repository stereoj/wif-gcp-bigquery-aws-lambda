#!/usr/bin/env bash
# Packages the Lambda deployment zip: handler + dependencies + credential-config.json.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f credential-config.json ]]; then
  echo "credential-config.json not found. Run scripts/generate_credential_config.sh first." >&2
  exit 1
fi

rm -rf build
mkdir -p build/package

pip install -r requirements.txt --target build/package --quiet

cp handler.py build/package/
cp credential-config.json build/package/

( cd build/package && zip -r ../function.zip . -x '*.pyc' -x '__pycache__/*' >/dev/null )

echo "Built build/function.zip ($(du -h build/function.zip | cut -f1))"
