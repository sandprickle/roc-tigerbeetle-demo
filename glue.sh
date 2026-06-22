#!/bin/bash

set -euo pipefail

roc glue ../oss/roc/src/glue/src/ZigGlue.roc ./src/ ./platform/main.roc
