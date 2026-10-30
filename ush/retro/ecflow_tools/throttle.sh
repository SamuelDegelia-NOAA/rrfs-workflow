#!/bin/bash
# Show or change how many cycles a RETRO_LAYOUT=chains retro runs at once (CYCLE_THROTTLE). The
# retro driver reads it on its next pass. Reloading the suites (start_retro.sh --reload) puts
# back the value in retro/config.sh.
#
# Usage: throttle.sh [N]

set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/suite_selection.sh"
retro_init_ecflow

if [ $# -eq 0 ]; then
  ecflow_client --get "/${PRODCLONE_SUITE}" | grep -m1 "edit CYCLE_THROTTLE"
elif [[ $1 =~ ^[1-9][0-9]*$ ]]; then
  ecflow_client --alter change variable CYCLE_THROTTLE "$1" "/${PRODCLONE_SUITE}"
  echo "CYCLE_THROTTLE set to $1 on /${PRODCLONE_SUITE}"
else
  echo "Usage: $(basename "$0") [N], N a positive whole number" >&2
  exit 1
fi
