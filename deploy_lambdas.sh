#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAMBDA_DIR="${ROOT_DIR}/terraform/lambda"
BUILD_DIR="${LAMBDA_DIR}/build"

if [ ! -d "${LAMBDA_DIR}" ]; then
  echo "No ${LAMBDA_DIR} directory found"
  exit 1
fi

echo "Packaging lambdas under ${LAMBDA_DIR} ..."

# Remove previous zips and build output so packaging starts clean
find "${LAMBDA_DIR}" -maxdepth 1 -type f -name "*.zip" -print0 | xargs -0 -r rm -f
rm -rf "${BUILD_DIR}"

# Build each function directory that looks like a Lambda function
# (contains a same-named .py file) into terraform/lambda/<name>.zip.
for dir in "${LAMBDA_DIR}"/*; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  [ "$name" = "build" ] && continue

  if [ ! -f "${dir}/${name}.py" ]; then
    echo "Skipping ${name} (no ${name}.py)"
    continue
  fi

  stage_dir="${BUILD_DIR}/${name}"
  zipfile="${LAMBDA_DIR}/${name}.zip"

  echo "Staging ${name} -> ${stage_dir}"
  mkdir -p "${stage_dir}"
  cp "${dir}/${name}.py" "${stage_dir}/"

  if [ -f "${dir}/requirements.txt" ]; then
    echo "Installing dependencies for ${name}"
    pip install --quiet --no-cache-dir -r "${dir}/requirements.txt" -t "${stage_dir}"
  fi

  echo "Packaging ${name} -> ${zipfile}"
  find "${stage_dir}" -name "__pycache__" -type d -prune -exec rm -rf {} +
  (cd "${stage_dir}" && zip -r -q "${zipfile}" . -x "*.dist-info/*" "*.egg-info/*" "*.pytest_cache/*")
done

rm -rf "${BUILD_DIR}"

echo "Lambda packaging complete. Zips are in ${LAMBDA_DIR}"
