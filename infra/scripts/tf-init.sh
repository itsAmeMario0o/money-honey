#!/usr/bin/env bash
# Thin wrapper around `terraform init`. Forwards any flags to terraform.
set -euo pipefail
cd "$(dirname "$0")/../terraform"
terraform init "$@"
