#!/bin/bash

source init.sh

DEFAULT_FILE="../exp.setup"
INPUT_FILE="${1:-$DEFAULT_FILE}"

source $INPUT_FILE

validated_yamls="${run_dir}/../../sorc/RDASApp/rrfs-test/validated_yamls"
currdir=`pwd`
cd $validated_yamls

###########################################
### Define the basic configuration YAML ###
###########################################

# EnVar
#basic_config="jedivar_base.yaml"
#fnialyaml="jedivar.yaml"
#distribution="RoundRobin"

# GETKF observer
basic_config="getkf_observer_base.yaml"
finalyaml="getkf_observer.yaml"
distribution="RoundRobin"

# GETKF solver
#basic_config="getkf_solver_base.yaml"
#finalyaml="getkf_solver.yaml"
#distribution="Halo"

# Analysis window length
length=4

# Define all observation type configurations
obtype_configs=(
    # Phase 3 - ready (just don't use specificHumidity yet!)
    "adpupa_airTemperature_120.yaml"
    "adpupa_specificHumidity_120.yaml"
    "adpupa_winds_220.yaml"
    "aircar_airTemperature_133.yaml"
    "aircar_specificHumidity_133.yaml"
    "aircar_winds_233.yaml"
    "aircft_airTemperature_130.yaml"
    "aircft_airTemperature_131.yaml"
    "aircft_airTemperature_134.yaml"
    "aircft_specificHumidity_134.yaml"
    "aircft_winds_230.yaml"
    "aircft_winds_231.yaml"
    "aircft_winds_234.yaml"
    "msonet_airTemperature_188.yaml"
    "msonet_specificHumidity_188.yaml"
    "msonet_stationPressure_188.yaml"
    "msonet_winds_288.yaml"

    # Phase 1 or 2 - not ready for MPAS-JEDI
    "adpsfc_airTemperature_181.yaml"
    "adpsfc_airTemperature_187.yaml"
    "adpsfc_specificHumidity_181.yaml"
    "adpsfc_specificHumidity_187.yaml"
    "adpsfc_stationPressure_181.yaml"
    "adpsfc_stationPressure_187.yaml"
    "adpsfc_winds_281.yaml"
    "adpsfc_winds_287.yaml"
    "proflr_winds_227.yaml"
    "rassda_airTemperature_126.yaml"
    "sfcshp_airTemperature_180.yaml"
    "sfcshp_specificHumidity_180.yaml"
    "sfcshp_stationPressure_180.yaml"
    "sfcshp_winds_280.yaml"

    # Need tested
    "adpsfc_airTemperature_183.yaml"
    "adpsfc_specificHumidity_183.yaml"
    "adpsfc_winds_284.yaml"
    "sfcshp_winds_282.yaml"
    "sfcshp_airTemperature_183.yaml"
    "sfcshp_specificHumidity_183.yaml"
    "sfcshp_winds_284.yaml"

    # no obs
    "adpupa_airTemperature_132.yaml"   # no obs
    "adpupa_specificHumidity_132.yaml" # no obs
    "adpupa_winds_232.yaml"            # no obs
    "sfcshp_airTemperature_182.yaml"   # no obs
    "sfcshp_specificHumidity_182.yaml" # no obs
    "sfcshp_stationPressure_182.yaml"  # no obs
    "aircft_airTemperature_135.yaml"   # no obs
    "aircft_winds_235.yaml"            # no obs

    # Needs more attention
    #"adpupa_stationPressure_120.yaml" # need python converter
    #"vadwnd_winds_224.yaml" # do last
)

rm -f ${finalyaml}  # Remove any existing file
rm -f input.yaml temp.yaml  # Remove any existing file

# Process each YAML file
declare -A processed_groups

for config in "${obtype_configs[@]}"; do
    echo "Appending YAMLs for $config"
    # Append YAML content
    cp ./templates/obtype_config/$config ./input.yaml
    if [[ $finalyaml == "getkf_solver.yaml" ]]; then
       ioda_file="data\/obs\/ioda_${config:0:6}.nc"
       jdiag_file="data\/jdiag\/jdiag_${config%?????}.nc4"
       sed -i "s/${ioda_file}/${jdiag_file}/g" ./input.yaml
    fi
    cat ./input.yaml >> temp.yaml
done

# Copy the basic configuration yaml into the super yaml
cp -p ${run_dir}/../../parm/$basic_config ./${finalyaml}

# Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
sed -i '/@OBSERVATIONS@/{
    r ./'"temp.yaml"'
    d
}' ./${finalyaml}
rm -f input.yaml temp.yaml # Clean up temporary yaml

# Temporary solution, replace actual date strings with placeholders
date_pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
sed -i -E \
    -e "s/date: &analysisDate '$date_pattern'/date: &analysisDate '@analysisDate@'/" \
    -e "s/begin: '$date_pattern'/begin: '@beginDate@'/" \
    -e "s/seed_time: \"$date_pattern\"/seed_time: '@analysisDate@'/" \
    -e "s/length: PT[0-9]H/length: 'PT${length}H'/" \
    -e "s/@DISTRIBUTION@/$distribution/" \
    -e "s/request_saturation_specific_humidity_geovals: true/request_saturation_specific_humidity_geovals: false/" \
    ./${finalyaml}

if [[ "${HYB_WGT_ENS}" == "0" ]] || [[ "${HYB_WGT_ENS}" == "0.0" ]]; then
    # deletes all lines from "covariance model: ensemble" to "weight:".
    sed -i '/covariance model: ensemble/,/weight:/d' ${finalyaml}
    # deletes the lines "- covariance:" is directly followed by "value: "@HYB_WGT_ENS@""
    sed -i '/- covariance:/ {N; /value: "@HYB_WGT_ENS@"/{d;}}' ${finalyaml}
elif [[ "${HYB_WGT_STATIC}" == "0" ]] || [[ "${HYB_WGT_STATIC}" == "0.0" ]]; then
    # deletes all lines from "covariance model: SABER" to "weight:".
    sed -i '/covariance model: SABER/,/weight:/d' ${finalyaml}
    # deletes the lines "- covariance:" is directly followed by "value: "@HYB_WGT_STATIC@""
    sed -i '/- covariance:/ {N; /value: "@HYB_WGT_STATIC@"/{d;}}' ${finalyaml}
fi

sed -i \
    -e "s/@HYB_WGT_STATIC@/${HYB_WGT_STATIC}/" \
    -e "s/@HYB_WGT_ENS@/${HYB_WGT_ENS}/" \
    ./${finalyaml}

echo "Super YAML created in ${finalyaml}"

# Save to where gen yamls was run
#cp -p ${finalyaml} ${run_dir}/.

# Save to parm directory
cp -p ${finalyaml} ${run_dir}/../../parm/.

echo "Generated ${finalyaml} to:"
echo "   ${run_dir}/../../parm/${finalyaml}"
