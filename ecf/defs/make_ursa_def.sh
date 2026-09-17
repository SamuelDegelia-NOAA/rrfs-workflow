#!/bin/bash
#
# Make an Ursa copy of an RRFS suite definition that submits jobs with Slurm.
# The task tree is unchanged; only suite-wide variables are replaced or added.
#
# Usage: [VAR=value ...] ./make_ursa_def.sh [output_def]
# Any of the settings below can be overridden from the environment.
#
set -eu

defs_dir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
out_def=${1:-${defs_dir}/rrfs_ursa.def}

# Suite definition to copy (relative to ecf/defs). nco_para triggers on the prod_clone suite for
# upstream (GFS, obsproc, ...) data; rrfs_prod.def is the retired FSM-based real-time suite.
BASE_DEF=${BASE_DEF:-nco_para/rrfs_nco_para.def}
# rrfs-workflow clone holding ecf/, jobs/, scripts/ and fix/
PACKAGEHOME=${PACKAGEHOME:-$(cd "${defs_dir}/../.." && pwd)}
# ecflow job files and job output (the server creates the task directories under it)
ECF_HOME=${ECF_HOME:-/scratch4/NCEPDEV/fv3-cam/${USER}/ecflow_rrfs/submit}
OUTPUTDIR=${OUTPUTDIR:-/scratch4/NCEPDEV/fv3-cam/${USER}/ecflow_rrfs/output}
# Slurm account (PROJ), QOS (QUEUE) and partition used in the #SBATCH lines of the ecf scripts
PROJ=${PROJ:-fv3-cam}
QUEUE=${QUEUE:-batch}
PARTITION=${PARTITION:-u1-compute}
# COMROOT is ${DEV_PTMP}/${USER}/ecflow_rrfs/para/com; DATAROOT holds the job working directories
DEV_PTMP=${DEV_PTMP:-/scratch4/NCEPDEV/fv3-cam/${USER}/ecflow_rrfs/ptmp}
DEV_DATAROOT=${DEV_DATAROOT:-/scratch4/NCEPDEV/fv3-cam/${USER}/ecflow_rrfs/stmp}
ECFLOW_VER=${ECFLOW_VER:-5.11.4}
# Upstream data in COM/DCOM layout (e.g. the retro link tree built by make_links.sh there)
RETRO_DATA_ROOT=${RETRO_DATA_ROOT:-/scratch4/BMC/zrtrr/Samuel.Degelia/RRFS_RETRO_DATA_NCO}
c=${RETRO_DATA_ROOT}/com
DEV_COMPATH=${DEV_COMPATH:-$c/gfs:$c/gefs:$c/obsproc:$c/nsst:$c/nosofs:$c/hrrr:$c/rap}
DCOMROOT=${DCOMROOT:-${RETRO_DATA_ROOT}/dcom}
# YES: neutralize the clock-time triggers for a retro (see the end of this script)
RETRO=${RETRO:-YES}
# Server-level variables on WCOSS2 that the NCO suites expect; nodes that set them keep their values
ENVIR=${ENVIR:-prod}
RRFS_VER=${RRFS_VER:-v1.0}
MACHINE_SITE=${MACHINE_SITE:-development}

awk -v q="'" -v ph="${PACKAGEHOME}" -v eh="${ECF_HOME}" -v od="${OUTPUTDIR}" \
    -v proj="${PROJ}" -v queue="${QUEUE}" -v part="${PARTITION}" \
    -v ptmp="${DEV_PTMP}" -v droot="${DEV_DATAROOT}" -v ev="${ECFLOW_VER}" \
    -v envir="${ENVIR}" -v rver="${RRFS_VER}" -v site="${MACHINE_SITE}" \
    -v compath="${DEV_COMPATH}" -v dcom="${DCOMROOT}" '
  function ed(name, value) { print ind "edit " name " " q value q }
  # suite-wide settings go right after the suite line
  $1 == "suite" && !done {
    print; ind = "  "; done = 1
    ed("MACHINE", "URSA")
    ed("PARTITION", part)
    ed("DEV_PTMP", ptmp)
    ed("DEV_DATAROOT", droot)
    ed("DEV_COMPATH", compath)
    ed("DCOMROOT", dcom)
    ed("ecflow_ver", ev)
    ed("ENVIR", envir)
    ed("rrfs_ver", rver)
    ed("MACHINE_SITE", site)
    ed("NET", "rrfs")
    ed("RUN", "rrfs")
    ed("PACKAGEHOME", ph)
    ed("PROJ", proj)
    ed("PROJENVIR", "DEV")
    ed("QUEUE", queue)
    ed("QUEUE_ARCH", queue)
    ed("OUTPUTDIR", od)
    ed("ECF_HOME", eh)
    ed("ECF_INCLUDE", ph "/ecf/include")
    # sbatch would otherwise also read the #PBS lines (e.g. "-q" as the partition)
    ed("ECF_JOB_CMD", "sbatch --ignore-pbs %ECF_JOB% 1> %ECF_JOB%.sub 2>&1")
    ed("ECF_KILL_CMD", "scancel %ECF_RID% 1> %ECF_JOB%.kill 2>&1")
    ed("ECF_STATUS_CMD", "squeue -j %ECF_RID% 1> %ECF_JOB%.stat 2>&1")
    next
  }
  # WCOSS2 locations and queues set further down would override the suite-level values
  $1 == "edit" && ($2 == "PACKAGEHOME" || $2 == "PROJ" || $2 == "QUEUE" || $2 == "QUEUE_ARCH" || $2 == "OUTPUTDIR") {
    ind = substr($0, 1, index($0, "edit") - 1)
    if ($2 == "PACKAGEHOME") ed("PACKAGEHOME", ph)
    if ($2 == "PROJ")        ed("PROJ", proj)
    if ($2 == "QUEUE")       ed("QUEUE", queue)
    if ($2 == "QUEUE_ARCH")  ed("QUEUE_ARCH", queue)
    if ($2 == "OUTPUTDIR")   ed("OUTPUTDIR", od)
    next
  }
  { print }
' "${defs_dir}/${BASE_DEF}" > "${out_def}"

# For retros, make every clock-time condition in the triggers always true; the dependencies on other
# tasks and on /prod_clone stay, and the retro prod_clone steps the dates (ush/prod_clone/make_retro_def.sh)
if [ "${RETRO}" = "YES" ]; then
  sed -i -E 's/:TIME *(>=|>) *[0-9]{4}/:TIME >= 0000/g; s/:TIME *(<=|<) *[0-9]{4}/:TIME < 2400/g' "${out_def}"
fi

echo "Wrote ${out_def} from ${BASE_DEF}"
echo "  PACKAGEHOME=${PACKAGEHOME}"
echo "  ECF_HOME=${ECF_HOME}  (create it before loading the suite)"
echo "  PROJ=${PROJ} QUEUE=${QUEUE} PARTITION=${PARTITION}"
echo "  DEV_PTMP=${DEV_PTMP}"
echo "  DEV_DATAROOT=${DEV_DATAROOT}"
echo "  RETRO_DATA_ROOT=${RETRO_DATA_ROOT}"
