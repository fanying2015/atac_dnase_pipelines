#!/usr/bin/env bash

set -o nounset
set -o pipefail
set -o errexit

module add bedtools/2.19.1
module add MACS2/2.0.10
module add ucsc_tools/2.7.2

readBed=$1
# This should really be shift size
fragLen=$2
genomeSize=$3
chrSize=$4

peakFile="${readBed}.pf"

# Shift reads by 75bp for peak calling
adjustedBed="slopBed -i ${readBed} -g ${chrSize} -l 75 -r -75 -s"

macs2 callpeak \
    -t <(${adjustedBed}) -f BED -n "${peakFile}" -g "${genomeSize}" -p 1e-2 \
    --nomodel --shift "${fragLen}" -B --SPMR --keep-dup all --call-summits

if [[ ! -e "${peakFile}.fc.signal.bigwig" ]]
then
    macs2 bdgcmp \
        -t "${peakFile}_treat_pileup.bdg" -c "${peakFile}_control_lambda.bdg" \
        --o-prefix "${peakFile}" -m FE
    slopBed -i "${peakFile}_FE.bdg" -g "${chrSize}" -b 0 | \
        bedClip stdin "${chrSize}" "${peakFile}.fc.signal.bedgraph"
    rm -f "${peakFile}_FE.bdg"
    bedGraphToBigWig "${peakFile}.fc.signal.bedgraph" "${chrSize}" "${peakFile}.fc.signal.bigwig"
    rm -f "${peakFile}.fc.signal.bedgraph"
fi

if [[ ! -e "${peakFile}.pval.signal.bigwig" ]]
then
    # sval counts the number of tags per million in the (compressed) BED file
    sval=$(wc -l <(zcat -f "${readBed}") | awk '{printf "%f", $1/1000000}')
    macs2 bdgcmp \
        -t "${peakFile}_treat_pileup.bdg" -c "${peakFile}_control_lambda.bdg" \
        --o-prefix "${peakFile}" -m ppois -S "${sval}"
    slopBed -i "${peakFile}_ppois.bdg" -g "${chrSize}" -b 0 | \
        bedClip stdin "${chrSize}" "${peakFile}.pval.signal.bedgraph"
    rm -f "${peakFile}_ppois.bdg"
    bedGraphToBigWig "${peakFile}.pval.signal.bedgraph" "${chrSize}" "${peakFile}.pval.signal.bigwig"
    rm -f "${peakFile}.pval.signal.bedgraph"
fi