#!/usr/bin/env bash
# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

./asr.sh \
    --lang ur \
    --asr_exp exp/asr_cs_bpe2000_RTX4000 \
    --ngpu 1 \
    --nj 16 \
    --asr_config conf/train_conformer_hybrid_rxt4000.yaml \
    --inference_config conf/decode_asr.yaml \
    --lm_config conf/train_lm.yaml \
    --train_set train \
    --valid_set valid \
    --test_sets test \
    --bpe_train_text "data/train/text" \
    --lm_train_text "data/train/text" "$@"
