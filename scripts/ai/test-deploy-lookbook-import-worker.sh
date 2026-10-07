#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node --test "$ROOT_DIR/scripts/ai/deploy-lookbook-import-worker.test.mjs"
