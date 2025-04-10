#!/bin/bash

#############################
### User-defined settings ###
#############################

# shellcheck disable=SC2154
run_dir=`pwd`
validated_yamls="${rundir}../../sorc/RDASApp/rrfs-test/validated_yamls"

# List of basic config files to use 
basic_configs=()
basic_configs+=(mpasjedi_hyb3denvar.yaml)
basic_configs+=(mpasjedi_getkf_observer.yaml)
basic_configs+=(mpasjedi_getkf_solver.yaml)

# Final yaml yamls
final_yamls=()
final_yamls+=(jedivar.yaml)
final_yamls+=(getkf_observer.yaml)
final_yamls+=(getkf_solver.yaml)

# Define all observation type configurations
obtype_configs=(
    "adpupa_airTemperature_120.yaml"
    "adpupa_specificHumidity_120.yaml"
    "adpupa_winds_220.yaml"
    "aircar_airTemperature_133.yaml"
    "aircar_specificHumidity_133.yaml"
    "aircar_winds_233.yaml"
    "aircft_airTemperature_130.yaml"
    "aircft_airTemperature_131.yaml"
    "aircft_airTemperature_134.yaml"
    "aircft_airTemperature_135.yaml"
    "aircft_specificHumidity_134.yaml"
    "aircft_winds_230.yaml"
    "aircft_winds_231.yaml"
    "aircft_winds_234.yaml"
    "aircft_winds_235.yaml"
    "msonet_airTemperature_188.yaml"
    "msonet_specificHumidity_188.yaml"
    "msonet_stationPressure_188.yaml"
    "adpsfc_airTemperature_181.yaml"
    "adpsfc_airTemperature_183.yaml"
    "adpsfc_airTemperature_187.yaml"
    "adpsfc_specificHumidity_181.yaml"
    "adpsfc_specificHumidity_183.yaml"
    "adpsfc_specificHumidity_187.yaml"
    "adpsfc_stationPressure_181.yaml"
    "adpsfc_stationPressure_187.yaml"
    "adpsfc_winds_281.yaml"
    "adpsfc_winds_284.yaml"
    "adpsfc_winds_287.yaml"
    "adpupa_airTemperature_132.yaml"
    "adpupa_specificHumidity_132.yaml"
    "msonet_winds_288.yaml"
    "proflr_winds_227.yaml"
    "rassda_airTemperature_126.yaml"
    "sfcshp_airTemperature_180.yaml"
    "sfcshp_airTemperature_182.yaml"
    "sfcshp_airTemperature_183.yaml"
    "sfcshp_specificHumidity_180.yaml"
    "sfcshp_specificHumidity_182.yaml"
    "sfcshp_specificHumidity_183.yaml"
    "sfcshp_stationPressure_180.yaml"
    "sfcshp_stationPressure_182.yaml"
    "sfcshp_winds_280.yaml"
    "sfcshp_winds_282.yaml"
    "sfcshp_winds_284.yaml"
    #"adpupa_stationPressure_120.yaml"
    #"vadwnd_winds_224.yaml" #not ready
)

#############################
### Begin executable code ###
#############################

source init.sh
DEFAULT_FILE="../exp.setup"
INPUT_FILE="${1:-$DEFAULT_FILE}"
# shellcheck disable=SC1090
source "$INPUT_FILE"
cd "$validated_yamls" || exit

# Which observation distribution to use? Halo or RoundRobin
distribution="RoundRobin"

# Analysis window length
length=4

# Loop over each yaml to process
icount=0
for basic_config in "${basic_configs[@]}"; do 

    final_yaml=${final_yamls[${icount}]}
    rm -f ${final_yaml}  # Remove any existing file
    rm -f temp.yaml  # Remove any existing file

    # Process each YAML file
    for config in "${obtype_configs[@]}"; do
        echo "Appending YAMLs for $config"
        # Append YAML content
        cat "./templates/obtype_config/$config" >> temp.yaml
        if [[ $final_yaml == "getkf_solver.yaml" ]]; then
            ioda_file="data\/obs\/ioda_${config:0:6}.nc"
            jdiag_file="data\/jdiag\/jdiag_${config%?????}.nc4"
            sed -i "s/${ioda_file}/${jdiag_file}/g" ./temp.yaml
        fi
    done

    # Copy the basic configuration yaml into the super yaml
    cp -p templates/basic_config/$basic_config ./${final_yaml}

    # Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
    sed -i '/@OBSERVATIONS@/{
      r ./'"temp.yaml"'
      d
    }' ./${final_yaml}

    rm -f temp.yaml # Clean up temporary yaml

    # Temporary solution, replace actual date strings with placeholders
    # Eventually the yaml templates in RDASApp will not be hardcoded 
    date_pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
    sed -i -E \
        -e "s/date: \&analysisDate '${date_pattern}'/date: \&analysisDate '@analysisDate@'/" \
        -e "s/begin: '$date_pattern'/begin: '@beginDate@'/" \
        -e "s/seed_time: \"$date_pattern\"/seed_time: '@analysisDate@'/" \
        -e "s/length: PT[0-9]H/length: 'PT${length}H'/" \
        -e "s/@DISTRIBUTION@/$distribution/" \
        -e "s/request_saturation_specific_humidity_geovals: true/request_saturation_specific_humidity_geovals: false/" \
        ./${final_yaml}

    if [[ "${HYB_WGT_ENS}" == "0" ]] || [[ "${HYB_WGT_ENS}" == "0.0" ]]; then
        # deletes all lines from "covariance model: ensemble" to "weight:".
        sed -i '/covariance model: ensemble/,/weight:/d' ${final_yaml}
        # deletes the lines "- covariance:" is directly followed by "value: "@HYB_WGT_ENS@""
        sed -i '/- covariance:/ {N; /value: "@HYB_WGT_ENS@"/{d;}}' ${final_yaml}
    elif [[ "${HYB_WGT_STATIC}" == "0" ]] || [[ "${HYB_WGT_STATIC}" == "0.0" ]]; then
        # deletes all lines from "covariance model: SABER" to "weight:".
        sed -i '/covariance model: SABER/,/weight:/d' ${final_yaml}
        # deletes the lines "- covariance:" is directly followed by "value: "@HYB_WGT_STATIC@""
        sed -i '/- covariance:/ {N; /value: "@HYB_WGT_STATIC@"/{d;}}' ${final_yaml}
    fi

    sed -i \
        -e "s/@HYB_WGT_STATIC@/${HYB_WGT_STATIC}/" \
        -e "s/@HYB_WGT_ENS@/${HYB_WGT_ENS}/" \
        ./${final_yaml}

    # Additional replacements for GETKF yamls 
    if [[ $final_yaml == "getkf_observer.yaml" ]] || [[ $final_yaml == "getkf_solver.yaml" ]]; then
        sed -i -E \
           -e "s/filename: \.\/bkg\.\\\$Y\-\\\$M\-\\\$D_\\\$h\.\\\$m\.\\\$s\.nc/filename: .\/prior_mean.nc/" \
           -e "s/filename: \.\/ana\.\\\$Y\-\\\$M\-\\\$D_\\\$h\.\\\$m\.\\\$s\.nc/filename: .\/data\/ens\/mem%\{member\}%.nc/" \
           -e "s/filename: \.\/data\/ens\/mem%iMember%\/mpasout\.[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.nc/filename: .\/data\/ens\/mem%iMember%.nc/" \
           ./${final_yaml}
        # Remove the five lines associated with the built-in JEDI testing
        sed -i "/test:/,+4d" ./${final_yaml}
    fi

    echo "Super YAML created in ${final_yaml}"

    # Save to parm directory
    mv ${final_yaml} "${run_dir}/../../parm/baseline_jedi_yamls/${final_yaml}"

    echo "Generated ${final_yaml} to:"
    echo -e "   ${run_dir}/../../parm/baseline_jedi_yamls/${final_yaml}\n\n"

    icount=$((icount+1))

done
