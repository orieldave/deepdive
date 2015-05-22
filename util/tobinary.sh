#!/usr/bin/env bash

# Script to convert grounding files in TSV format to binary format for dimmwitted sampler
# Usage: tobinary.sh INPUTFOLDER transform_script OUTPUTFOLDER
# It split the specific files in the input folder and for each of them calls the C++ binary to convert the format

set -eu

CHUNKSIZE=10000000
INPUTFOLDER=$1
transform_script=$2
OUTPUTFOLDER=$3

(
cd "$INPUTFOLDER"

rm -rf dd_tmp
mkdir -p dd_tmp
rm -rf dd_nedges_

# handle factors
while IFS=$'\t' read factor_name function_id positives; do
    _args=() nvars=0
    for p in $positives; do
        case $p in
            true) _args+=(1) ;;
            false) _args+=(0) ;;
        esac
        let ++nvars
    done

    echo "SPLITTING ${factor_name}..."
    split -a 10 -l $CHUNKSIZE dd_factors_${factor_name}_out dd_tmp/dd_factors_${factor_name}_out

    echo "BINARIZE ${factor_name}..."
    ls dd_tmp |
    egrep "^dd_factors_${factor_name}_out" |
    xargs -P 40 -I {} -n 1 \
        "$transform_script" factor dd_tmp/{} ${function_id} ${nvars} "${_args[@]}" |
    awk '{s+=$1} END {printf "%.0f\n", s}' >>dd_nedges_
done <dd_factormeta


# handle variables
for f in dd_variables_*; do
    echo "SPLITTING ${f}..."
    split -a 10 -l $CHUNKSIZE "${f}" dd_tmp/"${f}"

    echo "BINARIZE ${f}..."
    ls dd_tmp | egrep "^${f}" |
    xargs -P 40 -I {} -n 1 \
        "$transform_script" variable dd_tmp/{}
done

# handle weights
echo "BINARIZE weights..."
"$transform_script" weight dd_weights

# move files
rm -rf dd_factors
mkdir -p dd_factors
mv dd_tmp/dd_factors*.bin dd_factors/

rm -rf dd_variables
mkdir -p dd_variables
mv dd_tmp/dd_variables*.bin dd_variables/

# counting
echo "COUNTING variables..."
nvariables=$(wc -l dd_tmp/dd_variables_* | tail -n 1 | awk '{print $1}')

echo "COUNTING factors..."
nfactors=$(wc -l dd_tmp/dd_factors_* | tail -n 1 | awk '{print $1}')

echo "COUNTING weights..."
nweights=$(wc -l <dd_tmp/dd_weights)

echo "COUNTING edges..."
nedges=$(awk '{{ sum += $1 }} END {{ printf "%.0f\n", sum }}' dd_nedges_)

{
    echo "$nweights,$nvariables,$nfactors,$nedges"
    echo "$OUTPUTFOLDER"/graph.weights,"$OUTPUTFOLDER"/graph.variables,"$OUTPUTFOLDER"/graph.factors,"$OUTPUTFOLDER"/graph.edges
} >graph.meta

)

# concatenate files
echo "CONCATENATING FILES..."
if [[ "$INPUTFOLDER" != "$OUTPUTFOLDER" ]]; then
    mv  "$INPUTFOLDER"/graph.meta                         "$OUTPUTFOLDER"/graph.meta
    mv  "$INPUTFOLDER"/dd_weights.bin                     "$OUTPUTFOLDER"/dd_weights
    cat "$INPUTFOLDER"/dd_variables/*                    >"$OUTPUTFOLDER"/graph.variables
    cat "$INPUTFOLDER"/dd_factors/dd_factors*factors.bin >"$OUTPUTFOLDER"/graph.factors
    cat "$INPUTFOLDER"/dd_factors/dd_factors*edges.bin   >"$OUTPUTFOLDER"/graph.edges
fi

# clean up folder
echo "Cleaning up files"
rm -rf "$INPUTFOLDER"/dd_*
