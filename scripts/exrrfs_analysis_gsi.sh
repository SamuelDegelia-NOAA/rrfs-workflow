#!/bin/bash
#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHrrfs/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -e -u -x; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that runs a analysis with RRFS for the
specified cycle.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Configuration Parameters
#
#-----------------------------------------------------------------------
#
if [[ ! -v OB_TYPE ]]; then
  OB_TYPE="conv"
fi
export OB_TYPE=${OB_TYPE}

#export observer_gsi_dir=""
# GSI_TYPE = OBSERVER is only for EnKF (ensemble forecasts do not have ANALYSIS tasks)
#if [ "${GSI_TYPE}" = "OBSERVER" ]; then
#  if [ "${CYCLE_TYPE}" = "spinup" ]; then
#    observer_gsi_dir=${COMOUT}/observer_gsi_spinup
#  else
#    observer_gsi_dir=${COMOUT}/observer_gsi
#  fi
#  mkdir -p ${observer_gsi_dir}
#fi

# SATBIAS_DIR directory for cycling bias correction files
SATBIAS_DIR=$(compath.py -o ${NET}/${rrfs_ver}/satbias)
mkdir -p ${SATBIAS_DIR}
#
#-----------------------------------------------------------------------
#
# Set environment
#
#-----------------------------------------------------------------------
#
ulimit -a

case $MACHINE in
#
"WCOSS2")
#
  export FI_OFI_RXM_SAR_LIMIT=3145728
  export OMP_STACKSIZE=500M
  export OMP_NUM_THREADS=${TPP_ANALYSIS_GSI}
  ncores=$(( NNODES_ANALYSIS_GSI*PPN_ANALYSIS_GSI))
  APRUN="mpiexec -n ${ncores} -ppn ${PPN_ANALYSIS_GSI} --cpu-bind core --depth ${OMP_NUM_THREADS}"
  export COMINgfs="${COMINgfs:-$(compath.py gfs/${gfs_ver})}"
  ;;
#
"HERA")
  export OMP_NUM_THREADS=${TPP_ANALYSIS_GSI}
  export OMP_STACKSIZE=300M
  APRUN="srun"
  ;;
#
"ORION")
  export OMP_NUM_THREADS=${TPP_ANALYSIS_GSI}
  export OMP_STACKSIZE=1024M
  APRUN="srun"
  ;;
#
"HERCULES")
  export OMP_NUM_THREADS=${TPP_ANALYSIS_GSI}
  export OMP_STACKSIZE=1024M
  APRUN="srun"
  ;;
#
"JET")
  export OMP_NUM_THREADS=${TPP_ANALYSIS_GSI}
  export OMP_STACKSIZE=1024M
  APRUN="srun"
  ;;
#
esac
#
#-----------------------------------------------------------------------
#
# Extract from CDATE the starting year, month, day, and hour of the
# forecast.  These are needed below for various operations.
#
#-----------------------------------------------------------------------
#
START_DATE=$(echo "${CDATE}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')

YYYYMMDDHH=$(date +%Y%m%d%H -d "${START_DATE}")
JJJ=$(date +%j -d "${START_DATE}")

YYYY=${YYYYMMDDHH:0:4}
MM=${YYYYMMDDHH:4:2}
DD=${YYYYMMDDHH:6:2}
HH=${YYYYMMDDHH:8:2}
YYYYMMDD=${YYYYMMDDHH:0:8}
#
# YYYY-MM-DD_meso_uselist.txt and YYYYMMDD_rejects.txt:
# both contain past 7 day OmB averages till ~YYYYMMDD_23:59:59 UTC
# So they are to be used by next day cycles
MESO_USELIST_FN=$(date +%Y-%m-%d -d "${START_DATE} -1 day")_meso_uselist.txt
AIR_REJECT_FN=$(date +%Y%m%d -d "${START_DATE} -1 day")_rejects.txt
#
#-----------------------------------------------------------------------
#
# define fix and background path
#
#-----------------------------------------------------------------------
#
fixgriddir=$FIX_GSI/${PREDEF_GRID_NAME}
regional_ensemble_option=${regional_ensemble_option:-"5"}

if [ "${MEM_TYPE}" = "MEAN" ]; then
  bkpath=${FORECAST_INPUT_PRODUCT}
else
  bkpath=${FORECAST_INPUT_PRODUCT}
fi

# decide background type
if [ -r "${bkpath}/coupler.res" ]; then
  BKTYPE=0              # warm start
else
  BKTYPE=1              # cold start
  regional_ensemble_option=1
fi
l_both_fv3sar_gfs_ens=${l_both_fv3sar_gfs_ens:-".false."}
if  [ ${OB_TYPE} != "conv" ] || [ ${BKTYPE} -eq 1 ]; then #not using GDAS
  l_both_fv3sar_gfs_ens=.false.
fi
#
#---------------------------------------------------------------------
#
# decide regional_ensemble_option: global ensemble (1) or FV3LAM ensemble (5)
#
#---------------------------------------------------------------------
#
echo "regional_ensemble_option is ",${regional_ensemble_option:-1}
print_info_msg "$VERBOSE" "FIX_GSI is $FIX_GSI"
print_info_msg "$VERBOSE" "fixgriddir is $fixgriddir"
print_info_msg "$VERBOSE" "default bkpath is $bkpath"
print_info_msg "$VERBOSE" "background type is $BKTYPE"
#
# Check if we have enough RRFS ensembles when regional_ensemble_option=5
#
if  [[ ${regional_ensemble_option:-1} -eq 5 ]]; then
  ens_nstarthr=$( printf "%02d" ${DA_CYCLE_INTERV} )
  imem=1
  ifound=0
  for hrs in ${CYCL_HRS_HYB_FV3LAM_ENS[@]}; do
  if [ $HH == ${hrs} ]; then

  while [[ $imem -le ${NUM_ENS_MEMBERS} ]];do
    memcharv0=$( printf "%03d" $imem )
    memchar=m$( printf "%03d" $imem )

    YYYYMMDDInterv=$( date +%Y%m%d -d "${START_DATE} ${DA_CYCLE_INTERV} hours ago" )
    HHInterv=$( date +%H -d "${START_DATE} ${DA_CYCLE_INTERV} hours ago" )
    restart_prefix="${YYYYMMDD}.${HH}0000."
    bkpathmem=${COMrrfs}/enkfrrfs.${YYYYMMDDInterv}/${HHInterv}/${memchar}/forecast/RESTART
    if [ ${DO_SPINUP} == "TRUE" ]; then
      for cycl_hrs in ${CYCL_HRS_PRODSTART_ENS[@]}; do
       if [ $HH == ${cycl_hrs} ]; then
         bkpathmem=${COMrrfs}/enkfrrfs.${YYYYMMDDInterv}/${HHInterv}_spinup/${memchar}/forecast/RESTART
       fi
      done
    fi
    dynvarfile=${bkpathmem}/${restart_prefix}fv_core.res.tile1.nc
    tracerfile=${bkpathmem}/${restart_prefix}fv_tracer.res.tile1.nc
    phyvarfile=${bkpathmem}/${restart_prefix}phy_data.nc
    if [ -r "${dynvarfile}" ] && [ -r "${tracerfile}" ] && [ -r "${phyvarfile}" ] ; then
      ln -snf ${bkpathmem}/${restart_prefix}fv_core.res.tile1.nc       fv3SAR${ens_nstarthr}_ens_mem${memcharv0}-fv3_dynvars
      ln -snf ${bkpathmem}/${restart_prefix}fv_tracer.res.tile1.nc     fv3SAR${ens_nstarthr}_ens_mem${memcharv0}-fv3_tracer
      ln -snf ${bkpathmem}/${restart_prefix}phy_data.nc                fv3SAR${ens_nstarthr}_ens_mem${memcharv0}-fv3_phyvars
      (( ifound += 1 ))
    else
      print_info_msg "WARNING: Cannot find ensemble files: ${dynvarfile} ${tracerfile} ${phyvarfile} "
      date
      [[ -d ${bkpathmem} ]]&& ls -alrt ${bkpathmem}
    fi
    (( imem += 1 ))
  done
 
  fi
  done

  if [[ $ifound -ne ${NUM_ENS_MEMBERS} ]] || [[ ${BKTYPE} -eq 1 ]]; then
    print_info_msg "Not enough FV3_LAM ensembles, will fall to GDAS"
    regional_ensemble_option=1
    l_both_fv3sar_gfs_ens=.false.
  fi
fi
#
if  [[ ${regional_ensemble_option:-1} -eq 1 || ${l_both_fv3sar_gfs_ens} = ".true." ]]; then #using GDAS
  #-----------------------------------------------------------------------
  # Make a list of the latest GFS EnKF ensemble
  #-----------------------------------------------------------------------
  stampcycle=$(date -d "${START_DATE}" +%s)
  minHourDiff=100
  loops="009"    # or 009s for GFSv15
  ftype="nc"  # or nemsio for GFSv15
  foundgdasens="false"
  echo "no ens found" >> filelist03

  case $MACHINE in

  "WCOSS2")

    for loop in $loops; do
      for timelist in $(ls ${COMINgfs}/enkfgdas.*/*/atmos/mem080/gdas*.atmf${loop}.${ftype}); do
        availtimeyyyymmdd=$(echo ${timelist} | cut -d'/' -f9 | cut -c 10-17)
        availtimehh=$(echo ${timelist} | cut -d'/' -f10)
        availtime=${availtimeyyyymmdd}${availtimehh}
        avail_time=$(echo "${availtime}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')
        avail_time=$(date -d "${avail_time}")

        loopfcst=$(echo ${loop}| cut -c 1-3)      # for nemsio 009s to get 009
        stamp_avail=$(date -d "${avail_time} ${loopfcst} hours" +%s)

        hourDiff=$(echo "($stampcycle - $stamp_avail) / (60 * 60 )" | bc);
        if [[ ${stampcycle} -lt ${stamp_avail} ]]; then
           hourDiff=$(echo "($stamp_avail - $stampcycle) / (60 * 60 )" | bc);
        fi

        if [[ ${hourDiff} -lt ${minHourDiff} ]]; then
           minHourDiff=${hourDiff}
           enkfcstname=gdas.t${availtimehh}z.atmf${loop}
           eyyyymmdd=$(echo ${availtime} | cut -c1-8)
           ehh=$(echo ${availtime} | cut -c9-10)
           foundgdasens="true"
        fi
      done
    done

    if [ ${foundgdasens} = "true" ]
    then
      ls ${COMINgfs}/enkfgdas.${eyyyymmdd}/${ehh}/atmos/mem???/${enkfcstname}.nc > filelist03
    fi

    ;;
  "JET" | "HERA" | "ORION" | "HERCULES" )

    for loop in $loops; do
      for timelist in $(ls ${COMINgfs}/*.gdas.t*z.atmf${loop}.mem080.${ftype}); do
        availtimeyy=$(basename ${timelist} | cut -c 1-2)
        availtimeyyyy=20${availtimeyy}
        availtimejjj=$(basename ${timelist} | cut -c 3-5)
        availtimemm=$(date -d "${availtimeyyyy}0101 +$(( 10#${availtimejjj} - 1 )) days" +%m)
        availtimedd=$(date -d "${availtimeyyyy}0101 +$(( 10#${availtimejjj} - 1 )) days" +%d)
        availtimehh=$(basename ${timelist} | cut -c 6-7)
        availtime=${availtimeyyyy}${availtimemm}${availtimedd}${availtimehh}
        avail_time=$(echo "${availtime}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')
        avail_time=$(date -d "${avail_time}")

        loopfcst=$(echo ${loop}| cut -c 1-3)      # for nemsio 009s to get 009
        stamp_avail=$(date -d "${avail_time} ${loopfcst} hours" +%s)

        hourDiff=$(echo "($stampcycle - $stamp_avail) / (60 * 60 )" | bc);
        if [[ ${stampcycle} -lt ${stamp_avail} ]]; then
           hourDiff=$(echo "($stamp_avail - $stampcycle) / (60 * 60 )" | bc);
        fi

        if [[ ${hourDiff} -lt ${minHourDiff} ]]; then
           minHourDiff=${hourDiff}
           enkfcstname=${availtimeyy}${availtimejjj}${availtimehh}00.gdas.t${availtimehh}z.atmf${loop}
           foundgdasens="true"
        fi
      done
    done

    if [ $foundgdasens = "true" ]; then
      ls ${COMINgfs}/${enkfcstname}.mem0??.${ftype} >> filelist03
    fi

  esac
fi

#
#-----------------------------------------------------------------------
#
# set default values for namelist
#
#-----------------------------------------------------------------------
#
ifsatbufr=.false.
ifsoilnudge=.false.
ifhyb=.false.
miter=2
niter1=50
niter2=50
lread_obs_save=.false.
lread_obs_skip=.false.
if_model_dbz=.false.
nummem_gfs=0
nummem_fv3sar=0
anav_type=${OB_TYPE}
i_use_2mQ4B=2
i_use_2mT4B=1

# Determine if hybrid option is available
memname='atmf009'
grid_ratio_ens=${grid_ratio_ens:-"3"}
ens_fast_read=${ens_fast_read:-".false."}
HYBENSMEM_NMIN=${HYBENSMEM_NMIN:-"66"}
if [ ${regional_ensemble_option:-1} -eq 5 ]  && [ ${BKTYPE} != 1  ]; then 
  if [ ${l_both_fv3sar_gfs_ens} = ".true." ]; then
    nummem_gfs=$(more filelist03 | wc -l)
    nummem_gfs=$((nummem_gfs - 3 ))
  fi
  nummem_fv3sar=$NUM_ENS_MEMBERS
  nummem=`expr ${nummem_gfs} + ${nummem_fv3sar}`
  print_info_msg "$VERBOSE" "Do hybrid with FV3LAM ensemble"
  ifhyb=.true.
  print_info_msg "$VERBOSE" " Cycle ${YYYYMMDDHH}: GSI hybrid uses FV3LAM ensemble with n_ens=${nummem}" 
  echo " ${YYYYMMDDHH}(${CYCLE_TYPE}): GSI hybrid uses FV3LAM ensemble with n_ens=${nummem}"
  grid_ratio_ens="1"
  ens_fast_read=.false.
else    
  nummem_gfs=$(more filelist03 | wc -l)
  nummem_gfs=$((nummem_gfs - 3 ))
  nummem=${nummem_gfs}
  if [[ ${nummem} -ge ${HYBENSMEM_NMIN} ]]; then
    print_info_msg "$VERBOSE" "Do hybrid with ${memname}"
    ifhyb=.true.
    print_info_msg "$VERBOSE" " Cycle ${YYYYMMDDHH}: GSI hybrid uses ${memname} with n_ens=${nummem}"
    echo " ${YYYYMMDDHH}(${CYCLE_TYPE}): GSI hybrid uses ${memname} with n_ens=${nummem}"
  else
    print_info_msg "$VERBOSE" " Cycle ${YYYYMMDDHH}: GSI does pure 3DVAR."
    print_info_msg "$VERBOSE" " Hybrid needs at least ${HYBENSMEM_NMIN} ${memname} ensembles, only ${nummem} available"
    echo " ${YYYYMMDDHH}(${CYCLE_TYPE}): GSI dose pure 3DVAR"
  fi
  if [ "${anav_type}" = "conv_dbz" ]; then
    anav_type="conv"
  fi
fi
#
#-----------------------------------------------------------------------
#
# link or copy background and grib configuration files
#
#  Using ncks to add phis (terrain) into cold start input background.
#           it is better to change GSI to use the terrain from fix file.
#  Adding radar_tten array to fv3_tracer. Should remove this after add this array in
#           radar_tten converting code.
#-----------------------------------------------------------------------
#
n_iolayouty=$(($IO_LAYOUT_Y-1))
list_iolayout=$(seq 0 $n_iolayouty)

ln -snf ${fixgriddir}/fv3_akbk  fv3_akbk
ln -snf ${fixgriddir}/fv3_grid_spec  fv3_grid_spec

if [ ${BKTYPE} -eq 1 ]; then  # cold start uses background from INPUT
  ln -snf ${fixgriddir}/phis.nc  phis.nc
  ncks -A -v  phis  phis.nc  ${bkpath}/gfs_data.tile7.halo0.nc 

  ln -snf ${bkpath}/sfc_data.tile7.halo0.nc  fv3_sfcdata
  ln -snf ${bkpath}/gfs_data.tile7.halo0.nc  fv3_dynvars
  ln -s fv3_dynvars  fv3_tracer

  fv3lam_bg_type=1
else                          # cycle uses background from restart
  ln -snf ${bkpath}/fv_core.res.tile1.nc  fv3_dynvars
  ln -snf ${bkpath}/fv_tracer.res.tile1.nc  fv3_tracer
  ln -snf ${bkpath}/sfc_data.nc  fv3_sfcdata
  ln -snf ${bkpath}/phy_data.nc  fv3_phyvars
  fv3lam_bg_type=0
fi

# update times in coupler.res to current cycle time
cpreq -p ${fixgriddir}/fv3_coupler.res  coupler.res
sed -i "s/yyyy/${YYYY}/" coupler.res
sed -i "s/mm/${MM}/"     coupler.res
sed -i "s/dd/${DD}/"     coupler.res
sed -i "s/hh/${HH}/"     coupler.res

# copy xnorm and anl_grid for gsi performance 
if [ -r ${fixgriddir}/xnorm_new.480.1351.1976 ] && [ -r ${fixgriddir}/anl_grid.480.3950.2700 ]; then
  cpreq -p ${fixgriddir}/xnorm_new.480.1351.1976 .
  cpreq -p ${fixgriddir}/anl_grid.480.3950.2700 .
fi
if [ -r ${fixgriddir}/xnorm_new.240.1351.1976 ] && [ -r ${fixgriddir}/anl_grid.240.3950.2700 ]; then
  cpreq -p ${fixgriddir}/xnorm_new.240.1351.1976 .
  cpreq -p ${fixgriddir}/anl_grid.240.3950.2700 .
fi

#
#-----------------------------------------------------------------------
#
# link observation files
# copy observation files to working directory 
#
#-----------------------------------------------------------------------
OBSPATH=${OBSPATH:-$(compath.py obsproc/${obsproc_ver})}
if [[ "${NET}" = "RTMA"* ]] && [[ "${RTMA_OBS_FEED}" = "NCO" ]]; then
  SUBH=$(date +%M -d "${START_DATE}")
  obs_source="rtma_ru"
  obsfileprefix=${obs_source}
  obspath_tmp=${OBSPATH}/${obs_source}.${YYYYMMDD}
else
  SUBH=""
  obs_source=${OBSTYPE_SOURCE}
  if [ ${HH} -eq '00' ] || [ ${HH} -eq '12' ]; then
    if [ ${GSI_TYPE} == "OBSERVER" ]; then
      obs_source=${OBSTYPE_SOURCE}_e
    else
      obs_source=${OBSTYPE_SOURCE}
    fi
  fi

  case $MACHINE in

  "WCOSS2")
     obsfileprefix=${obs_source}
     obspath_tmp=${OBSPATH}/${obs_source}.${YYYYMMDD}
    ;;
  "JET" | "HERA")
     obsfileprefix=${YYYYMMDDHH}.${obs_source}
     obspath_tmp=${OBSPATH}
    ;;
  "ORION" | "HERCULES")
     obs_source=${OBSTYPE_SOURCE}
     obsfileprefix=${YYYYMMDDHH}.${obs_source}               # observation from JET.
     #obsfileprefix=${obs_source}.${YYYYMMDD}/${obs_source}    # observation from operation.
     obspath_tmp=${OBSPATH}
    ;;
  *)
     obsfileprefix=${obs_source}
     obspath_tmp=${OBSPATH}
  esac
fi

if [[ ${GSI_TYPE} == "OBSERVER" || ${anav_type} == "conv" || ${anav_type} == "conv_dbz" ]]; then

  obs_files_source[0]=${obspath_tmp}/${obsfileprefix}.t${HH}${SUBH}z.prepbufr.tm00
  obs_files_target[0]=prepbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}${SUBH}z.satwnd.tm00.bufr_d
  obs_files_target[${obs_number}]=satwndbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}${SUBH}z.nexrad.tm00.bufr_d
  obs_files_target[${obs_number}]=l2rwbufr

  if [ "${anav_type}" = "conv_dbz" ]; then
    obs_number=${#obs_files_source[@]}
    obs_files_source[${obs_number}]=${umbrella_init_data}/output/Gridded_ref.nc
    obs_files_target[${obs_number}]=dbzobs.nc
    if [ "${DO_GLM_FED_DA}" = "TRUE" ]; then
      obs_number=${#obs_files_source[@]}
      obs_files_source[${obs_number}]=${umbrella_init_data}/output/fedobs.nc
      obs_files_target[${obs_number}]=fedobs.nc
    fi
  fi

  if [ "${DO_ENKF_RADAR_REF}" = "TRUE" ]; then
    obs_number=${#obs_files_source[@]}
    obs_files_source[${obs_number}]=${umbrella_init_data}/output/Gridded_ref.nc
    obs_files_target[${obs_number}]=dbzobs.nc
    if [ "${DO_GLM_FED_DA}" = "TRUE" ]; then
      obs_number=${#obs_files_source[@]}
      obs_files_source[${obs_number}]=${umbrella_init_data}/output/fedobs.nc
      obs_files_target[${obs_number}]=fedobs.nc
    fi
  fi

else

  if [ "${anav_type}" = "radardbz" ]; then
    obs_files_source[0]=${umbrella_init_data}/output/Gridded_ref.nc
    obs_files_target[0]=dbzobs.nc
    if [ "${DO_GLM_FED_DA}" = "TRUE" ]; then
      obs_files_source[1]=${umbrella_init_data}/output/fedobs.nc
      obs_files_target[1]=fedobs.nc
    fi
  fi

fi
#
#-----------------------------------------------------------------------
#
# including satellite radiance data
#
#-----------------------------------------------------------------------
if [[ ${GSI_TYPE} == "OBSERVER" || ${anav_type} == "conv" || ${anav_type} == "conv_dbz" ]]; then
  if [ "${DO_RADDA}" = "TRUE" ]; then

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.1bamua.tm00.bufr_d
  obs_files_target[${obs_number}]=amsuabufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esamua.tm00.bufr_d
  obs_files_target[${obs_number}]=amsuabufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.1bmhs.tm00.bufr_d
  obs_files_target[${obs_number}]=mhsbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esmhs.tm00.bufr_d
  obs_files_target[${obs_number}]=mhsbufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.atms.tm00.bufr_d
  obs_files_target[${obs_number}]=atmsbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esatms.tm00.bufr_d
  obs_files_target[${obs_number}]=atmsbufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.atmsdb.tm00.bufr_d
  obs_files_target[${obs_number}]=atmsbufr_db

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.crisf4.tm00.bufr_d
  obs_files_target[${obs_number}]=crisfsbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.crsfdb.tm00.bufr_d
  obs_files_target[${obs_number}]=crisfsbufr_db

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.mtiasi.tm00.bufr_d
  obs_files_target[${obs_number}]=iasibufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esiasi.tm00.bufr_d
  obs_files_target[${obs_number}]=iasibufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.iasidb.tm00.bufr_d
  obs_files_target[${obs_number}]=iasibufr_db

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.gsrcsr.tm00.bufr_d
  obs_files_target[${obs_number}]=abibufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.ssmisu.tm00.bufr_d
  obs_files_target[${obs_number}]=ssmisbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.sevcsr.tm00.bufr_d
  obs_files_target[${obs_number}]=sevcsr

  fi
fi

obs_number=${#obs_files_source[@]}
for (( i=0; i<${obs_number}; i++ ));
do
  obs_file=${obs_files_source[$i]}
  obs_file_t=${obs_files_target[$i]}
  if [ -r "${obs_file}" ]; then
    ln -s "${obs_file}" "${obs_file_t}"
  else
    print_info_msg "$VERBOSE" "WARNING: ${obs_file} does not exist!"
  fi
done

#
#-----------------------------------------------------------------------
#
# Create links to fix files in the FIXgsi directory.
# Set fixed files
#   berror   = forecast model background error statistics
#   specoef  = CRTM spectral coefficients
#   trncoef  = CRTM transmittance coefficients
#   emiscoef = CRTM coefficients for IR sea surface emissivity model
#   aerocoef = CRTM coefficients for aerosol effects
#   cldcoef  = CRTM coefficients for cloud effects
#   satinfo  = text file with information about assimilation of brightness temperatures
#   satangl  = angle dependent bias correction file (fixed in time)
#   pcpinfo  = text file with information about assimilation of prepcipitation rates
#   ozinfo   = text file with information about assimilation of ozone data
#   errtable = text file with obs error for conventional data (regional only)
#   convinfo = text file with information about assimilation of conventional data
#   bufrtable= text file ONLY needed for single obs test (oneobstest=.true.)
#   bftab_sst= bufr table for sst ONLY needed for sst retrieval (retrieval=.true.)
#
#-----------------------------------------------------------------------
#
ANAVINFO_FN=${ANAVINFO_FN:-"anavinfo.rrfs"}
ANAVINFO=${FIX_GSI}/${ANAVINFO_FN}
diag_radardbz=${diag_radardbz:-".false."}
diag_fed=${diag_fed:-".false."}
if_model_fed=${if_model_fed:-".false."}
innov_use_model_fed=${innov_use_model_fed:-".false."}
beta1_inv=${beta1_inv:-"0.15"}
ANAVINFO_DBZ_FN=${ANAVINFO_DBZ_FN:-"anavinfo.rrfs_dbz"}
if [ "${DO_ENKF_RADAR_REF}" = "TRUE" ]; then
  ANAVINFO=${FIX_GSI}/${ANAVINFO_DBZ_FN}
  diag_radardbz=.true.
  if [ "${DO_GLM_FED_DA}" = "TRUE" ]; then
    diag_fed=.true.
  fi
  beta1_inv=0.0
  if_model_dbz=.true.
fi
bkgerr_hzscl=${bkgerr_hzscl:-"0.7,1.4,2.80"}
readin_localization=${readin_localization:-".false."}
ens_h=${ens_h:-"328.632,82.1580,4.10790,4.10790,82.1580"}
ens_v=${ens_v:-"3,3,-0.30125,-0.30125,0.0"}
ens_h_radardbz=${ens_h_radardbz:-"4.10790"}
ens_v_radardbz=${ens_v_radardbz:-"-0.30125"}
nsclgrp=${nsclgrp:-"2"}
ngvarloc=${ngvarloc:-"2"}
r_ensloccov4tim=${r_ensloccov4tim:-"1.0"}
r_ensloccov4var=${r_ensloccov4var:-"0.05"}
r_ensloccov4scl=${r_ensloccov4scl:-"1.0"}
q_hyb_ens=${q_hyb_ens:-".false."}
assign_vdl_nml=${assign_vdl_nml:-".false."}
ANAVINFO_CONV_DBZ_FN=${ANAVINFO_CONV_DBZ_FN:-"anavinfo.rrfs_conv_dbz"}
ANAVINFO_CONV_DBZ_FED_FN=${ANAVINFO_CONV_DBZ_FED_FN:-"anavinfo.rrfs_conv_dbz_fed"}
ANAVINFO_DBZ_FED_FN=${ANAVINFO_DBZ_FED_FN:-"anavinfo.rrfs_dbz_fed"}
ENKF_ANAVINFO_DBZ_FN=${ENKF_ANAVINFO_DBZ_FN:-"anavinfo.enkf.rrfs_dbz"}
CONVINFO_FN=${CONVINFO_FN:-"convinfo.rrfs"}
BERROR_FN=${BERROR_FN:-"rrfs_glb_berror.l127y770.f77"}
OBERROR_FN=${OBERROR_FN:-"errtable.rrfs"}
HYBENSINFO_FN=${HYBENSINFO_FN:-"hybens_info.rrfs"}
if [[ ${GSI_TYPE} == "ANALYSIS" && ${anav_type} == "radardbz" ]]; then
  ANAVINFO=${FIX_GSI}/${ENKF_ANAVINFO_DBZ_FN}
  if [ "${DO_GLM_FED_DA}" = "TRUE" ]; then
    myStr=$( ncdump -h fv3_phyvars | grep flash_extent_density );
    if [ ${#myStr} -ge 5 ]; then
      ANAVINFO=${FIX_GSI}/${ANAVINFO_DBZ_FED_FN}
      diag_fed=.true.
      if_model_fed=.true.
      innov_use_model_fed=.true.
    fi
  fi
  miter=1
  niter1=100
  niter2=0
  bkgerr_vs=0.1
  bkgerr_hzscl="0.4,0.5,0.6"
  beta1_inv=0.0
  readin_localization=.false.
  ens_h=${ens_h_radardbz}
  ens_v=${ens_v_radardbz}
  nsclgrp=1
  ngvarloc=1
  r_ensloccov4tim=1.0
  r_ensloccov4var=1.0
  r_ensloccov4scl=1.0
  q_hyb_ens=.true.
  if_model_dbz=.true.
fi
if [[ ${GSI_TYPE} == "ANALYSIS" && ${anav_type} == "conv_dbz" ]]; then
  ANAVINFO=${FIX_GSI}/${ANAVINFO_CONV_DBZ_FN}
  if_model_dbz=.true.
  if [ "${DO_GLM_FED_DA}" = "TRUE" ]; then
    myStr=$( ncdump -h fv3_phyvars | grep flash_extent_density );
    if [ ${#myStr} -ge 5 ]; then
      ANAVINFO=${FIX_GSI}/${ANAVINFO_CONV_DBZ_FED_FN}
      diag_fed=.true.
      if_model_fed=.true.
      innov_use_model_fed=.true.
    fi
  fi
fi
naensloc=`expr ${nsclgrp} \* ${ngvarloc} + ${nsclgrp} - 1`
if [ ${assign_vdl_nml} = ".true." ]; then
  nsclgrp=`expr ${nsclgrp} \* ${ngvarloc}`
  ngvarloc=1
fi
CONVINFO=${FIX_GSI}/${CONVINFO_FN}
HYBENSINFO=${FIX_GSI}/${HYBENSINFO_FN}
OBERROR=${FIX_GSI}/${OBERROR_FN}
BERROR=${FIX_GSI}/${BERROR_FN}
write_diag_2=${write_diag_2:-".false."}
usenewgfsberror=${usenewgfsberror:-".true."}
netcdf_diag=${netcdf_diag:-".true."}
binary_diag=${binary_diag:-".false."}
laeroana_fv3smoke=${laeroana_fv3smoke:-".false."}
berror_fv3_cmaq_regional=${berror_fv3_cmaq_regional:-".false."}
berror_fv3_sd_regional=${berror_fv3_sd_regional:-".false."}
ANAVINFO_SD_FN=${ANAVINFO_SD_FN:-"anavinfo.rrfs_sd"}
CONVINFO_SD_FN=${CONVINFO_SD_FN:-"convinfo.rrfs_sd"}
BERROR_SD_FN=${BERROR_SD_FN:-"berror.rrfs_sd"}

if [[ ${GSI_TYPE} == "ANALYSIS" && ${anav_type} == "AERO" ]]; then
  if [ ${BKTYPE} -eq 1 ]; then
    echo "cold start, skip GSI SD DA"
    exit 0
  fi
  ANAVINFO=${FIX_GSI}/${ANAVINFO_SD_FN}
  CONVINFO=${FIX_GSI}/${CONVINFO_SD_FN}
  BERROR=${FIX_GSI}/${BERROR_SD_FN}
  miter=1
  niter1=100
  niter2=0
  write_diag_2=.true.
  ifhyb=.false.
  ifsd_da=.true.
  l_hyb_ens=.false.
  nummem=0
  beta1_inv=0.0
  i_use_2mQ4B=0
  i_use_2mT4B=0
  netcdf_diag=.true.
  binary_diag=.false.
  usenewgfsberror=.false.
  laeroana_fv3smoke=.true.
#remove cmaq when GSL GSI is update in future
  berror_fv3_cmaq_regional=.true.
  berror_fv3_sd_regional=.true.
fi

SATINFO=${FIX_GSI}/global_satinfo.txt
OZINFO=${FIX_GSI}/global_ozinfo.txt
PCPINFO=${FIX_GSI}/global_pcpinfo.txt
ATMS_BEAMWIDTH=${FIX_GSI}/atms_beamwidth.txt

# Fixed fields
cpreq -p ${ANAVINFO} anavinfo
cpreq -p ${BERROR}   berror_stats
cpreq -p $SATINFO    satinfo
cpreq -p $CONVINFO   convinfo
cpreq -p $OZINFO     ozinfo
cpreq -p $PCPINFO    pcpinfo
cpreq -p $OBERROR    errtable
cpreq -p $ATMS_BEAMWIDTH atms_beamwidth.txt
cpreq -p ${HYBENSINFO} hybens_info

# Get surface observation provider list
if [ -r ${FIX_GSI}/gsd_sfcobs_provider.txt ]; then
  cpreq -p ${FIX_GSI}/gsd_sfcobs_provider.txt gsd_sfcobs_provider.txt
else
  print_info_msg "$VERBOSE" "WARNING: gsd surface observation provider does not exist!" 
fi

# Get aircraft reject list
for reject_list in "${AIRCRAFT_REJECT}/current_bad_aircraft.txt" \
                   "${AIRCRAFT_REJECT}/${AIR_REJECT_FN}"
do
  if [ -r $reject_list ]; then
    cpreq -p $reject_list current_bad_aircraft
    print_info_msg "$VERBOSE" "Use aircraft reject list: $reject_list "
    break
  fi
done
if [ ! -r $reject_list ] ; then 
  print_info_msg "$VERBOSE" "WARNING: gsd aircraft reject list does not exist!" 
fi

# Get mesonet uselist
gsd_sfcobs_uselist="gsd_sfcobs_uselist.txt"
for use_list in "${SFCOBS_USELIST}/current_mesonet_uselist.txt" \
                "${SFCOBS_USELIST}/${MESO_USELIST_FN}"      \
                "${SFCOBS_USELIST}/gsd_sfcobs_uselist.txt"
do 
  if [ -r $use_list ] ; then
    cpreq -p $use_list  $gsd_sfcobs_uselist
    print_info_msg "$VERBOSE" "Use surface obs uselist: $use_list "
    break
  fi
done
if [ ! -r $use_list ] ; then 
  print_info_msg "$VERBOSE" "WARNING: gsd surface observation uselist does not exist!" 
fi
#
#-----------------------------------------------------------------------
#
# CRTM Spectral and Transmittance coefficients
# set coefficient under crtm_coeffs_path='./crtm_coeffs/',
#-----------------------------------------------------------------------
#
emiscoef_IRwater=${FIX_CRTM}/Nalli.IRwater.EmisCoeff.bin
emiscoef_IRice=${FIX_CRTM}/NPOESS.IRice.EmisCoeff.bin
emiscoef_IRland=${FIX_CRTM}/NPOESS.IRland.EmisCoeff.bin
emiscoef_IRsnow=${FIX_CRTM}/NPOESS.IRsnow.EmisCoeff.bin
emiscoef_VISice=${FIX_CRTM}/NPOESS.VISice.EmisCoeff.bin
emiscoef_VISland=${FIX_CRTM}/NPOESS.VISland.EmisCoeff.bin
emiscoef_VISsnow=${FIX_CRTM}/NPOESS.VISsnow.EmisCoeff.bin
emiscoef_VISwater=${FIX_CRTM}/NPOESS.VISwater.EmisCoeff.bin
emiscoef_MWwater=${FIX_CRTM}/FASTEM6.MWwater.EmisCoeff.bin
aercoef=${FIX_CRTM}/AerosolCoeff.bin
cldcoef=${FIX_CRTM}/CloudCoeff.bin

mkdir -p crtm_coeffs
ln -s ${emiscoef_IRwater} ./crtm_coeffs/Nalli.IRwater.EmisCoeff.bin
ln -s $emiscoef_IRice ./crtm_coeffs/NPOESS.IRice.EmisCoeff.bin
ln -s $emiscoef_IRsnow ./crtm_coeffs/NPOESS.IRsnow.EmisCoeff.bin
ln -s $emiscoef_IRland ./crtm_coeffs/NPOESS.IRland.EmisCoeff.bin
ln -s $emiscoef_VISice ./crtm_coeffs/NPOESS.VISice.EmisCoeff.bin
ln -s $emiscoef_VISland ./crtm_coeffs/NPOESS.VISland.EmisCoeff.bin
ln -s $emiscoef_VISsnow ./crtm_coeffs/NPOESS.VISsnow.EmisCoeff.bin
ln -s $emiscoef_VISwater ./crtm_coeffs/NPOESS.VISwater.EmisCoeff.bin
ln -s $emiscoef_MWwater ./crtm_coeffs/FASTEM6.MWwater.EmisCoeff.bin
ln -s $aercoef  ./crtm_coeffs/AerosolCoeff.bin
ln -s $cldcoef  ./crtm_coeffs/CloudCoeff.bin

# Copy CRTM coefficient files based on entries in satinfo file
for file in $(awk '{if($1!~"!"){print $1}}' ./satinfo | sort | uniq) ;do
   ln -s ${FIX_CRTM}/${file}.SpcCoeff.bin ./crtm_coeffs/.
   ln -s ${FIX_CRTM}/${file}.TauCoeff.bin ./crtm_coeffs/.
done

#-----------------------------------------------------------------------
#
# cycling radiance bias corretion files
#
#-----------------------------------------------------------------------
if [ "${DO_RADDA}" = "TRUE" ]; then
  if [ "${CYCLE_TYPE}" = "spinup" ]; then
    echo "spin up cycle"
    spinup_or_prod_rrfs=spinup
    for cyc_start in "${CYCL_HRS_SPINSTART[@]}"; do
      if [ ${HH} -eq ${cyc_start} ]; then
        spinup_or_prod_rrfs=prod 
      fi
    done
  else 
    echo " product cycle"
    spinup_or_prod_rrfs=prod
    for cyc_start in "${CYCL_HRS_PRODSTART[@]}"; do
      if [ ${HH} -eq ${cyc_start} ]; then
        spinup_or_prod_rrfs=spinup      
      fi 
    done
  fi

  satcounter=1
  maxcounter=240
  while [ $satcounter -lt $maxcounter ]; do
    SAT_TIME=`date +"%Y%m%d%H" -d "${START_DATE}  ${satcounter} hours ago"`
    echo $SAT_TIME

# DO_ENS_RADDA IS NEVER TRUE - REMOVE THIS IF BLOCK?	
#    if [ "${DO_ENS_RADDA}" = "TRUE" ]; then			
#      # For EnKF.  Note, EnKF does not need radstat file
#      if [ -r ${SATBIAS_DIR}_ensmean/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias ]; then
#        echo " using satellite bias files from ${SAT_TIME}" 
#        cpreq -p ${SATBIAS_DIR}_ensmean/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias ./satbias_in
#        cpreq -p ${SATBIAS_DIR}_ensmean/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias_pc ./satbias_pc
#	    
#        break
#      fi
	  
#    else
    # For EnVar
    if [ -r ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias ]; then
      echo " using satellite bias files from ${SATBIAS_DIR} ${spinup_or_prod_rrfs}.${SAT_TIME}"
      cpreq -p ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias ./satbias_in
      cpreq -p ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias_pc ./satbias_pc
      if [ -r ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_radstat ]; then
         cpreq -p ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_radstat ./radstat.rrfs
      fi

      break
    fi
	
    satcounter=` expr $satcounter + 1 `
  done

  ## if satbias files (go back to previous 10 days) are not available from ${SATBIAS_DIR}, use satbias files from the ${FIX_GSI} 
  if [ $satcounter -eq $maxcounter ]; then
    # satbias_in
    if [ -r ${FIX_GSI}/rrfs.starting_satbias ]; then
      echo "using satelite satbias_in files from ${FIX_GSI}"     
      cpreq -p ${FIX_GSI}/rrfs.starting_satbias ./satbias_in
    fi
	  	  
    # satbias_pc
    if [ -r ${FIX_GSI}/rrfs.starting_satbias_pc ]; then
      echo "using satelite satbias_pc files from ${FIX_GSI}"     
      cpreq -p ${FIX_GSI}/rrfs.starting_satbias_pc ./satbias_pc
    fi
  fi

  if [ -r radstat.rrfs ]; then
    listdiag=`tar xvf radstat.rrfs | cut -d' ' -f2 | grep _ges`
    for type in $listdiag; do
      diag_file=`echo $type | cut -d',' -f1`
      fname=`echo $diag_file | cut -d'.' -f1`
      date=`echo $diag_file | cut -d'.' -f2`
      gunzip $diag_file
      fnameanl=$(echo $fname|sed 's/_ges//g')
      mv $fname.$date* $fnameanl
    done
  fi
fi

#-----------------------------------------------------------------------
# skip radar reflectivity analysis if no RRFSE ensemble
#-----------------------------------------------------------------------

if [[ ${GSI_TYPE} == "ANALYSIS" && ${anav_type} == "radardbz" ]]; then
  if  [[ ${regional_ensemble_option:-1} -eq 1 ]]; then
    echo "No RRFSE ensemble available, cannot do radar reflectivity analysis"
    exit 0
  fi
fi
#-----------------------------------------------------------------------
#
# Build the GSI namelist on-the-fly
#    most configurable paramters take values from settings in config.sh
#                                             (var_defns.sh in runtime)
#
#-----------------------------------------------------------------------
# 
if [ "${GSI_TYPE}" = "OBSERVER" ]; then
  miter=0
  ifhyb=.false.
  if [ "${MEM_TYPE}" = "MEAN" ]; then
    lread_obs_save=.true.
    lread_obs_skip=.false.
  else
    lread_obs_save=.false.
    lread_obs_skip=.true.
    if [ "${CYCLE_TYPE}" = "spinup" ]; then
      ln -s ${umbrella_analysis_data}/${RUN}_observer_gsi_spinup_ensmean_${envir}_${cyc}/obs_input.* .
    else
      ln -s ${umbrella_analysis_data}/${RUN}_observer_gsi_ensmean_${envir}_${cyc}/obs_input.* .
    fi
  fi
fi
if [ ${BKTYPE} -eq 1 ]; then
  n_iolayouty=1
else
  n_iolayouty=$(($IO_LAYOUT_Y))
fi

. ${USHrrfs}/gsiparm.anl.sh
cat << EOF > gsiparm.anl
$gsi_namelist
EOF
#
#-----------------------------------------------------------------------
#
# Run the GSI.  Note that we have to launch the forecast from
# the current cycle's run directory because the GSI executable will look
# for input files in the current directory.
#
#-----------------------------------------------------------------------
#
gsi_exec="${EXECrrfs}/gsi.x"
cpreq -p ${gsi_exec} ${DATA}/gsi.x

export pgm="gsi.x"
. prep_step

$APRUN ./$pgm < gsiparm.anl >>$pgmout 2>errfile
export err=$?; err_chk
cpreq -p $pgmout $COMOUT/rrfs.t${HH}z.gsiout.tm00
cpreq -p $pgmout rrfs.t${HH}z.gsiout.tm00

mv errfile errfile_gsi

if [ "${anav_type}" = "radardbz" ]; then
  cat fort.238 > $COMOUT/rrfs.t${HH}z.fits3.tm00
else
  mv fort.207 fit_rad1
  [[ -s fort.201 ]]&& sed -e 's/   asm all     /ps asm 900 0000/; s/   rej all     /ps rej 900 0000/; s/   mon all     /ps mon 900 0000/' fort.201 > fit_p1
  [[ -s fort.202 ]]&& sed -e 's/   asm all     /uv asm 900 0000/; s/   rej all     /uv rej 900 0000/; s/   mon all     /uv mon 900 0000/' fort.202 > fit_w1
  [[ -s fort.203 ]]&& sed -e 's/   asm all     / t asm 900 0000/; s/   rej all     / t rej 900 0000/; s/   mon all     / t mon 900 0000/' fort.203 > fit_t1
  [[ -s fort.204 ]]&& sed -e 's/   asm all     / q asm 900 0000/; s/   rej all     / q rej 900 0000/; s/   mon all     / q mon 900 0000/' fort.204 > fit_q1
  [[ -s fort.205 ]]&& sed -e 's/   asm all     /pw asm 900 0000/; s/   rej all     /pw rej 900 0000/; s/   mon all     /pw mon 900 0000/' fort.205 > fit_pw1
  [[ -s fort.209 ]]&& sed -e 's/   asm all     /rw asm 900 0000/; s/   rej all     /rw rej 900 0000/; s/   mon all     /rw mon 900 0000/' fort.209 > fit_rw1

  for file_to_cat in fit_p1 fit_w1 fit_t1 fit_q1 fit_pw1 fit_rad1 fit_rw1; do
    [[ -s ${file_to_cat} ]]&& cat ${file_to_cat} >> $COMOUT/rrfs.t${HH}z.fits.tm00
  done
  for file_to_cat in fort.208 fort.210 fort.211 fort.212 fort.213 fort.220; do
    [[ -s ${file_to_cat} ]]&& cat ${file_to_cat} >> $COMOUT/rrfs.t${HH}z.fits2.tm00
  done
  [[ -s fort.238 ]]&& cat fort.238 > $COMOUT/rrfs.t${HH}z.fits3.tm00
fi
#
#-----------------------------------------------------------------------
#
# touch a file "gsi_complete.txt" after the successful GSI run. This is to inform
# the successful analysis for the EnKF recentering
#
#-----------------------------------------------------------------------
#
touch ${COMOUT}/gsi_complete.txt
if [[ ${anav_type} == "radardbz" || ${anav_type} == "conv_dbz" ]]; then
  touch ${COMOUT}/gsi_complete_radar.txt # for nonvarcldanl
fi
#
#-----------------------------------------------------------------------
# Loop over first and last outer loops to generate innovation
# diagnostic files for indicated observation types (groups)
#
# NOTE:  Since we set miter=2 in GSI namelist SETUP, outer
#        loop 03 will contain innovations with respect to 
#        the analysis.  Creation of o-a innovation files
#        is triggered by write_diag(3)=.true.  The setting
#        write_diag(1)=.true. turns on creation of o-g
#        innovation files.
#-----------------------------------------------------------------------
#
if [ "${DO_GSIDIAG_OFFLINE}" = "FALSE" ]; then
  netcdf_diag=${netcdf_diag:-".false."}
  binary_diag=${binary_diag:-".true."}

  loops="01 03"
  for loop in $loops; do

  case $loop in
    01) string=ges;;
    03) string=anl;;
     *) string=$loop;;
  esac

  #  Collect diagnostic files for obs types (groups) below
  numfile_rad_bin=0
  numfile_cnv=0
  numfile_rad=0
  if [ $binary_diag = ".true." ]; then
    listall="hirs2_n14 msu_n14 sndr_g08 sndr_g11 sndr_g11 sndr_g12 sndr_g13 sndr_g08_prep sndr_g11_prep sndr_g12_prep sndr_g13_prep sndrd1_g11 sndrd2_g11 sndrd3_g11 sndrd4_g11 sndrd1_g15 sndrd2_g15 sndrd3_g15 sndrd4_g15 sndrd1_g13 sndrd2_g13 sndrd3_g13 sndrd4_g13 hirs3_n15 hirs3_n16 hirs3_n17 amsua_n15 amsua_n16 amsua_n17 amsua_n18 amsua_n19 amsua_metop-a amsua_metop-b amsua_metop-c amsub_n15 amsub_n16 amsub_n17 hsb_aqua airs_aqua amsua_aqua imgr_g08 imgr_g11 imgr_g12 pcp_ssmi_dmsp pcp_tmi_trmm conv sbuv2_n16 sbuv2_n17 sbuv2_n18 omi_aura ssmi_f13 ssmi_f14 ssmi_f15 hirs4_n18 hirs4_metop-a mhs_n18 mhs_n19 mhs_metop-a mhs_metop-b mhs_metop-c amsre_low_aqua amsre_mid_aqua amsre_hig_aqua ssmis_las_f16 ssmis_uas_f16 ssmis_img_f16 ssmis_env_f16 iasi_metop-a iasi_metop-b iasi_metop-c seviri_m08 seviri_m09 seviri_m10 seviri_m11 cris_npp atms_npp ssmis_f17 cris-fsr_npp cris-fsr_n20 atms_n20 abi_g16 abi_g18 radardbz fed atms_n21 cris-fsr_n21"
    for type in $listall; do
      count=$(ls pe*.${type}_${loop} | wc -l)
      if [[ $count -gt 0 ]]; then
         $(cat pe*.${type}_${loop} > diag_${type}_${string}.${YYYYMMDDHH})
         cp diag_${type}_${string}.${YYYYMMDDHH} $COMOUT
         echo "diag_${type}_${string}.${YYYYMMDDHH}" >> listrad_bin
         numfile_rad_bin=`expr ${numfile_rad_bin} + 1`
      fi
    done
  fi

  if [ "$netcdf_diag" = ".true." ]; then
    export pgm="nc_diag_cat.x"

    listall_cnv="conv_ps conv_q conv_t conv_uv conv_pw conv_rw conv_sst conv_dbz conv_fed"
    listall_rad="hirs2_n14 msu_n14 sndr_g08 sndr_g11 sndr_g11 sndr_g12 sndr_g13 sndr_g08_prep sndr_g11_prep sndr_g12_prep sndr_g13_prep sndrd1_g11 sndrd2_g11 sndrd3_g11 sndrd4_g11 sndrd1_g15 sndrd2_g15 sndrd3_g15 sndrd4_g15 sndrd1_g13 sndrd2_g13 sndrd3_g13 sndrd4_g13 hirs3_n15 hirs3_n16 hirs3_n17 amsua_n15 amsua_n16 amsua_n17 amsua_n18 amsua_n19 amsua_metop-a amsua_metop-b amsua_metop-c amsub_n15 amsub_n16 amsub_n17 hsb_aqua airs_aqua amsua_aqua imgr_g08 imgr_g11 imgr_g12 pcp_ssmi_dmsp pcp_tmi_trmm conv sbuv2_n16 sbuv2_n17 sbuv2_n18 omi_aura ssmi_f13 ssmi_f14 ssmi_f15 hirs4_n18 hirs4_metop-a mhs_n18 mhs_n19 mhs_metop-a mhs_metop-b mhs_metop-c amsre_low_aqua amsre_mid_aqua amsre_hig_aqua ssmis_las_f16 ssmis_uas_f16 ssmis_img_f16 ssmis_env_f16 iasi_metop-a iasi_metop-b iasi_metop-c seviri_m08 seviri_m09 seviri_m10 seviri_m11 cris_npp atms_npp ssmis_f17 cris-fsr_npp cris-fsr_n20 atms_n20 abi_g16 abi_g18 atms_n21 cris-fsr_n21"

    for type in $listall_cnv; do
      count=$(ls pe*.${type}_${loop}.nc4 | wc -l)
      if [[ $count -gt 0 ]]; then
	 . prep_step
         ${APRUN} $pgm -o diag_${type}_${string}.${YYYYMMDDHH}.nc4 pe*.${type}_${loop}.nc4 >>$pgmout 2>errfile
	 export err=$?; err_chk
	 mv errfile errfile_nc_diag_cat_$type
         if [[ -s diag_${type}_${string}.${YYYYMMDDHH}.nc4 ]]; then
           gzip diag_${type}_${string}.${YYYYMMDDHH}.nc4
           cp diag_${type}_${string}.${YYYYMMDDHH}.nc4.gz ${COMOUT}
           echo "diag_${type}_${string}.${YYYYMMDDHH}.nc4.gz" >> listcnv
         numfile_cnv=`expr ${numfile_cnv} + 1`
         fi
      fi
    done

    for type in $listall_rad; do
      count=$(ls pe*.${type}_${loop}.nc4 | wc -l)
      if [[ $count -gt 0 ]]; then
        . prep_step
        ${APRUN} $pgm -o diag_${type}_${string}.${YYYYMMDDHH}.nc4 pe*.${type}_${loop}.nc4 >>$pgmout 2>errfile
	export err=$?; err_chk
	mv errfile errfile_nc_diag_cat_$type
        gzip diag_${type}_${string}.${YYYYMMDDHH}.nc4
        cp diag_${type}_${string}.${YYYYMMDDHH}.nc4.gz ${COMOUT}
        echo "diag_${type}_${string}.${YYYYMMDDHH}.nc4.gz" >> listrad
        numfile_rad=`expr ${numfile_rad} + 1`
      else
        echo 'No diag_' ${type} 'exist'
      fi
    done
  fi
  done

  if [ "${GSI_TYPE}" = "OBSERVER" ]; then
    if [ "${MEM_TYPE}" = "MEAN" ]; then
      if [ "${CYCLE_TYPE}" = "spinup" ]; then
        mkdir -p ${umbrella_analysis_data}/${RUN}_observer_gsi_spinup_ensmean_${envir}_${cyc}
        cp obs_input.* ${umbrella_analysis_data}/${RUN}_observer_gsi_spinup_ensmean_${envir}_${cyc}/.
      else
        mkdir -p ${umbrella_analysis_data}/${RUN}_observer_gsi_ensmean_${envir}_${cyc}
        cp obs_input.* ${umbrella_analysis_data}/${RUN}_observer_gsi_ensmean_${envir}_${cyc}/.
      fi
    fi
  fi
  #
  #-----------------------------------------------------------------------
  #
  # cycling radiance bias corretion files
  #
  #-----------------------------------------------------------------------
  #
  if [ "${DO_RADDA}" = "TRUE" ]; then
    if [ "${CYCLE_TYPE}" = "spinup" ]; then
      spinup_or_prod_rrfs=spinup
    else
      spinup_or_prod_rrfs=prod
    fi
    if [ ${numfile_cnv} -gt 0 ]; then
      tar -cvzf rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_cnvstat_nc `cat listcnv`
      cp ./rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_cnvstat_nc  ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_cnvstat
    fi
    if [ ${numfile_rad} -gt 0 ]; then
      tar -cvzf rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat_nc `cat listrad`
      cp ./rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat_nc  ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat
    fi
    if [ ${numfile_rad_bin} -gt 0 ]; then
      tar -cvzf rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat `cat listrad_bin`
      cp ./rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat  ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat
    fi

    # For EnVar DA  
    cp ./satbias_out ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_satbias
    cp ./satbias_pc.out ${SATBIAS_DIR}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_satbias_pc
    cp ./satbias_out ${COMOUT}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_satbias
    cp ./satbias_pc.out ${COMOUT}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_satbias_pc
  fi
fi # run diag inline (with GSI)

# 
#-----------------------------------------------------------------------
# 
# Copy output files to Umbrella Shared DATA location
# 
#-----------------------------------------------------------------------
#
filelist="pe*.nc4 rrfs.*.${YYYYMMDDHH}_cnvstat_nc rrfs.*.${YYYYMMDDHH}_radstat_nc satbias_out satbias_pc.out"
for file in $filelist; do
  if [ -s $file ]; then
    [[ -f ${shared_output_data}/${file} ]]&& rm -f ${shared_output_data}/${file}
    echo "ln -s ${DATA}/${file} ." >> ${shared_output_data}/link_shared_file.sh
  else
    echo "WARNING $file is not available"
  fi
done
cd ${shared_output_data}
sh -x link_shared_file.sh
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
ANALYSIS GSI completed successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/function.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1

