#!/usr/bin/env bash
# Thin wrapper around `terraform plan`. Saves the plan to ./tfplan so
# `terraform apply tfplan` later uses the exact reviewed changes.
set -euo pipefail
cd "$(dirname "$0")/../terraform"
terraform plan -out=tfplan "$@"
