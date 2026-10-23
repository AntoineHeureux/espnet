#!/usr/bin/env bash
# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

log() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}
SECONDS=0

stage=1
stop_stage=100

datadir=./data
ndev_utt=100

log "$0 $*"
. utils/parse_options.sh

if [ $# -ne 0 ]; then
    log "Error: No positional arguments are required."
    exit 2
fi

. ./path.sh
. ./cmd.sh

train_set="train"
train_dev="valid"


if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    log "stage 1: Data preparation (using existing local data directory)"
    mkdir -p ${datadir}

    # Ensure expected subdirs exist (no download in this recipe)
    mkdir -p ${datadir}/train ${datadir}/test ${datadir}/valid

    # For each split, sort the main Kaldi files and produce spk2utt
    for x in train test valid; do
        if [ -d ${datadir}/${x} ]; then
            for f in text wav.scp utt2spk utt2dur; do
                if [ -f ${datadir}/${x}/${f} ]; then
                    sort ${datadir}/${x}/${f} -o ${datadir}/${x}/${f}
                fi
            done
            if [ -f ${datadir}/${x}/utt2spk ]; then
                utils/utt2spk_to_spk2utt.pl ${datadir}/${x}/utt2spk > "${datadir}/${x}/spk2utt"
            fi
        else
            log "Warning: expected directory ${datadir}/${x} not found."
        fi
    done
fi

log "Successfully finished. [elapsed=${SECONDS}s]"
