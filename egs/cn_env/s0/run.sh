#!/bin/bash
# Copyright  2019 Jiayu DU

#-------------------- RESOURCES --------------------#
## Database
DB=/data/disk001

aidatatang_train=$DB/aidatatang_200zh/train
aidatatang_dev=$DB/aidatatang_200zh/dev
aidatatang_test=$DB/aidatatang_200zh/test

AISHELL1_train=$DB/AISHELL-1/train
AISHELL1_dev=$DB/AISHELL-1/dev
AISHELL1_test=$DB/AISHELL-1/test

AISHELL2_iOS_train=$DB/AISHELL-2/iOS/train
AISHELL2_iOS_dev=$DB/AISHELL-2/iOS/dev
AISHELL2_iOS_test=$DB/AISHELL-2/iOS/test

AISHELL2_Android_train=$DB/AISHELL-2/Android/train
AISHELL2_Android_dev=$DB/AISHELL-2/Android/dev
AISHELL2_Android_test=$DB/AISHELL-2/Android/test

AISHELL7=$DB/AISHELL-7/data

magicdata_train=$DB/magicdata/train
magicdata_dev=$DB/magicdata/dev
magicdata_test=$DB/magicdata/test

mobile_2000h=$DB/mobile_2000h/data
primewords=$DB/primewords/data
stcmds=$DB/stcmds/data

## AM training & testing data
trn_list=""
#trn_list="$trn_list aidatatang_train aidatatang_dev"
trn_list="$trn_list AISHELL1_train AISHELL1_dev"
trn_list="$trn_list AISHELL2_iOS_train AISHELL2_iOS_dev"
trn_list="$trn_list AISHELL2_Android_train AISHELL2_Android_dev"
trn_list="$trn_list AISHELL7"
trn_list="$trn_list magicdata_train magicdata_dev"
trn_list="$trn_list mobile_2000h"
trn_list="$trn_list primewords"
trn_list="$trn_list stcmds"

tst_list=""
#tst_list="$tst_list aidatatang_test" 
tst_list="$tst_list AISHELL1_test" 
tst_list="$tst_list AISHELL2_iOS_test AISHELL2_Android_test" 
tst_list="$tst_list magicdata_test" 

## Pronounciation Lexicon
raw_lexicon=prepare/lexicon.txt

## LM training corpus
lm_text=prepare/text.txt

#-------------------- CONFIG --------------------#
nj=20
stage=0
gmm_stage=1

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

#
if [ $stage -le 1 ]; then
  sh local/prepare_dict.sh $raw_lexicon data/local/dict || exit 1;

  # generate jieba's word-seg vocab, it requires word count(frequency), set to 99
  awk '{print $1}' data/local/dict/lexicon.txt | sort | uniq | awk '{print $1,99}' > data/local/dict/ws_vocab.txt
fi

# prepare acoustic data & transcriptions
if [ $stage -le 2 ]; then
  for s in $trn_list; do
    name=$s
    path=`eval echo '$'$s`
    sh local/prepare_am_data.sh ${path} data/local/dict/ws_vocab.txt data/local/${name} data/${name} || exit 1;
  done

  for s in $tst_list; do
    name=$s
    path=`eval echo '$'$s`
    sh local/prepare_am_data.sh ${path} data/local/dict/ws_vocab.txt data/local/${name} data/${name} || exit 1;
  done
fi

if [ $stage -le 3 ]; then
  echo "Combine training sets"
  combine_list=""
  for s in $trn_list; do
    if [ -z $combine_list ]; then
      combine_list=$s
    else
      combine_list="$combine_list,$s"
    fi
  done
  cmd="utils/combine_data.sh data/train_all data/{$combine_list}"
  #echo $cmd
  eval $cmd

  echo "Combine testing sets"
  combine_list=""
  for s in $tst_list; do
    if [ -z $combine_list ]; then
      combine_list=$s
    else
      combine_list="$combine_list,$s"
    fi
  done
  cmd="utils/combine_data.sh data/test_all data/{$combine_list}"
  #echo $cmd
  eval $cmd
fi

if [ $stage -le 4 ]; then
  utils/subset_data_dir.sh data/train_all 310000 data/train
  utils/subset_data_dir.sh data/test_all 1000 data/dev
  utils/subset_data_dir.sh data/test_all 1000 data/test
fi

# L
if [ $stage -le 5 ]; then
  utils/prepare_lang.sh --position-dependent-phones false \
    data/local/dict "<UNK>" data/local/lang data/lang || exit 1;
fi

# LM training 
if [ $stage -le 6 ]; then
  dir=data/local/lm
  mkdir -p $dir

  # text normalization
  python3 local/cn_tn.py --to_upper $lm_text $dir/tmp

  # word segmentation
  python3 local/cn_ws.py data/local/dict/ws_vocab.txt $dir/tmp $dir/text  || exit 1;

  # train arpa
  local/train_arpa.sh data/local/dict/lexicon.txt $dir/text $dir || exit 1;
fi

# G compilation, check LG composition
if [ $stage -le 7 ]; then
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
