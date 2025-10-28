#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAMBDA_DIR="${ROOT_DIR}/terraform/lambda"

if [ ! -d "${LAMBDA_DIR}" ]; then
  echo "No ${LAMBDA_DIR} directory found"
  exit 1
fi

echo "Packaging lambdas under ${LAMBDA_DIR} ..."

# Remove previous zips so packaging starts clean
find "${LAMBDA_DIR}" -maxdepth 1 -type f -name "*.zip" -print0 | xargs -0 -r rm -f

# Zip each subdirectory into terraform/lambda/<name>.zip, excluding caches and packaging metadata
for dir in "${LAMBDA_DIR}"/*; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  # Only package directories that look like Lambda functions (contain a same-named .py file)
  if [ ! -f "${dir}/${name}.py" ]; then
    echo "Skipping ${name} (no ${name}.py)"
    continue
  fi
  zipfile="${LAMBDA_DIR}/${name}.zip"
  echo "Packaging ${name} -> ${zipfile}"
  # create a clean zip: exclude __pycache__ and packaging metadata
  (cd "$dir" && zip -r -q "${zipfile}" . -x "__pycache__/*" "*.dist-info/*" "*.egg-info/*" "*.pytest_cache/*")
done

echo "Lambda packaging complete. Zips are in ${LAMBDA_DIR}"