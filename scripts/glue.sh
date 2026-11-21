#!/bin/bash

set -euo pipefail

roc glue "$ROC_DIR"/src/glue/src/ZigGlue.roc ./src/ ./platform/main.roc
zig fmt "./src/roc_platform_abi.zig"
