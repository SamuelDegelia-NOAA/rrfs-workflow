#!/bin/bash
#
# Source the retro settings, ecf/defs/retro_config.sh, into the calling script. It is sourced by
# setup_ecf_links.sh, make_rrfs_retro_def.sh, ush/prod_clone/make_retro_def.sh and
# ush/retro/start_retro.sh, so they agree on where the file is and what happens when it is missing.
#
# Usage: . load_retro_config.sh [--optional]
#   --optional  return 1 quietly when there is no settings file instead of exiting; for
#               setup_ecf_links.sh, which also runs outside retros
#
# retro_config.sh is git-ignored; link or copy one of the retro_config_<machine>_<domain>.sh samples
# to it. ursa_config.sh, its name before the retros ran outside Ursa, is still read when it is the
# only one there.

_retro_defs_dir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
if [ -f "${_retro_defs_dir}/retro_config.sh" ]; then
  # shellcheck source=/dev/null
  . "${_retro_defs_dir}/retro_config.sh"
elif [ -f "${_retro_defs_dir}/ursa_config.sh" ]; then
  echo "NOTE: reading ecf/defs/ursa_config.sh; it is now called retro_config.sh, so rename it" >&2
  # shellcheck source=/dev/null
  . "${_retro_defs_dir}/ursa_config.sh"
elif [ "${1:-}" = "--optional" ]; then
  unset _retro_defs_dir
  return 1
else
  echo "ecf/defs/retro_config.sh not found." >&2
  echo "Link or copy the sample for your machine and domain, e.g." >&2
  echo "  ln -s retro_config_ursa_na3km.sh ecf/defs/retro_config.sh" >&2
  exit 1
fi
unset _retro_defs_dir
# Settings files from before MACHINE was a setting were all for Ursa
MACHINE=${MACHINE:-URSA}
# The NA sample leaves DOMAIN out; default it here so every script that reads it agrees
DOMAIN=${DOMAIN:-RRFS_NA_3km}
