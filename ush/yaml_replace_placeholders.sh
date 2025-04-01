#!/usr/bin/env bash
# generate the JEDI yaml file using the jedivar.yaml from the parm/ directory
#
inyaml=${1:-jedivar.yaml}
cp -p ${PARMrrfs}/${inyaml} .

sed -i \
    -e "s/@analysisDate@/${analysisDate}/" \
    -e "s/@beginDate@/${beginDate}/" \
    ./${inyaml}
