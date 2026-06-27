#!/bin/bash

set -euo pipefail

"$ROC_BIN" glue "$ROC_DIR"/src/glue/src/ZigGlue.roc ./src/ ./platform/main.roc
