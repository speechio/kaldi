#!/bin/bash
# Copyright  2019 Jiayu DU

#-------------------- RESOURCES --------------------#
# 1. AM training corpus
# trn_set=/disk10/data/AISHELL-2/iOS/data
# dev_set=/disk10/data/AISHELL-2/iOS/dev
# tst_set=/disk10/data/AISHELL-2/iOS/test
trn_set=/data/disk001/AISHELL-2/iOS/train
dev_set=/data/disk001/AISHELL-2/iOS/dev
tst_set=/data/disk001/AISHELL-2/iOS/test

# 2. Pronounciation Lexicon
raw_lexicon=prepare/lexicon.txt

# 3. LM training corpus
lm_text=prepare/text.txt

#-------------------- CONFIG --------------------#
nj=20
stage=1
gmm_stage=1

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

#
if [ $stage -le 1 ]; then
  local/prepare_dict.sh $raw_lexicon data/local/dict || exit 1;

  # generate jieba's word-seg vocab, it requires word count(frequency), set to 99
  awk '{print $1}' data/local/dict/lexicon.txt | sort | uniq | awk '{print $1,99}' > data/local/dict/word_seg_vocab.txt
fi

# wav.scp, text(word-segmented), utt2spk, spk2utt
if [ $stage -le 2 ]; then
  local/prepare_am_data.sh $trn_set data/local/dict/word_seg_vocab.txt data/local/train data/train || exit 1;
  local/prepare_am_data.sh $dev_set data/local/dict/word_seg_vocab.txt data/local/dev   data/dev   || exit 1;
  local/prepare_am_data.sh $tst_set data/local/dict/word_seg_vocab.txt data/local/test  data/test  || exit 1;
fi

# L
if [ $stage -le 3 ]; then
  utils/prepare_lang.sh --position-dependent-phones false \
    data/local/dict "<UNK>" data/local/lang data/lang || exit 1;
fi

# LM training 
if [ $stage -le 4 ]; then
  dir=data/local/lm
  mkdir -p $dir

  # text normalization
  python3 local/cn_tn.py --to_upper $lm_text $dir/tmp

  # word segmentation
  python3 local/cn_ws.py data/local/dict/word_seg_vocab.txt $dir/tmp $dir/text  || exit 1;

  # train arpa
  local/train_arpa.sh data/local/dict/lexicon.txt $dir/text $dir || exit 1;
fi

# G compilation, check LG composition
if [ $stage -le 5 ]; then
  utils/format_lm.sh data/lang data/local/lm/3gram-mincount/lm_unpruned.gz \
    data/local/dict/lexicon.txt data/lang_test || exit 1;
fi

# GMM
if [ $stage -le 10 ]; then
  local/run_gmm.sh --nj $nj --stage $gmm_stage
fi

# chain
if [ $stage -le 20 ]; then
  local/chain/run_tdnn.sh --nj $nj
fi

local/show_results.sh

exit 0;
