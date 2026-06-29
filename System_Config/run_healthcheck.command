#!/bin/bash
DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$DIR/System_Config/healthcheck.sh"
open "$DIR/System_Config/status_page.html"
