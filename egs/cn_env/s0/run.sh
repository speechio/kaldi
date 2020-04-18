#!/bin/bash
# Copyright  2019 Jiayu DU

#-------------------- RESOURCES --------------------#
## Database
DB=/data/audio

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

mobile_0007=$DB/mobile_0007/data

magicdata_train=$DB/magicdata/train
magicdata_dev=$DB/magicdata/dev
magicdata_test=$DB/magicdata/test

mobile_2000h=$DB/mobile_2000h/data
primewords=$DB/primewords/data
stcmds=$DB/stcmds/data

#-------------------- CONFIG --------------------#
## AM training & testing data
trn_list=""
#trn_list="$trn_list aidatatang_train aidatatang_dev"
trn_list="$trn_list AISHELL1_train AISHELL1_dev"
trn_list="$trn_list AISHELL2_iOS_train AISHELL2_iOS_dev"
trn_list="$trn_list AISHELL2_Android_train AISHELL2_Android_dev"
trn_list="$trn_list mobile_0007"
trn_list="$trn_list magicdata_train magicdata_dev"
trn_list="$trn_list mobile_2000h"
trn_list="$trn_list primewords"
trn_list="$trn_list stcmds"

tst_list=""
#tst_list="$tst_list aidatatang_test" 
tst_list="$tst_list AISHELL1_test" 
tst_list="$tst_list AISHELL2_iOS_test" 
tst_list="$tst_list AISHELL2_Android_test" 
tst_list="$tst_list magicdata_test" 

## Pronounciation Lexicon
raw_lexicon=prepare/lexicon.txt

## LM training corpus
lm_text=prepare/text.txt

#-----------------------------------------------#

STEP_PREP_DICT=1
STEP_PREP_AM_DATA=1
STEP_COMBINE_AM_DATA=1
STEP_SUBSET_AM_DATA=1
STEP_PREP_LANG=1
STEP_TRAIN_LM=1
STEP_TRAIN_GMM=1
STEP_TRAIN_DNN=1
STEP_SHOW_RESULTS=1

num_utts_gmm=5000
num_utts_dnn=10000
num_utts_test=100

#-----------------------------------------------#
nj=20
gmm_stage=0
dnn_stage=0

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if [ $STEP_PREP_DICT -eq 1 ]; then
  sh local/prepare_dict.sh $raw_lexicon data/local/dict || exit 1;
  # generate jieba's word-seg vocab, it requires word count(frequency), set to 99
  awk '{print $1}' data/local/dict/lexicon.txt | sort | uniq | awk '{print $1,99}' > data/local/dict/ws_vocab.txt
fi

if [ $STEP_PREP_AM_DATA -eq 1 ]; then
  for x in $trn_list $tst_list; do
    path=`eval echo '$'$x`
    sh local/prepare_am_data.sh ${path} data/local/dict/ws_vocab.txt data/local/$x data/$x || exit 1;
  done
fi

if [ $STEP_COMBINE_AM_DATA -eq 1 ]; then
  cmd="utils/combine_data.sh data/train_all"
  for x in $trn_list; do
    cmd="$cmd data/$x"
  done
  eval $cmd
  echo "Training Sets Combined."

  cmd="utils/combine_data.sh data/test_all"
  for x in $tst_list; do
    cmd="$cmd data/$x"
  done
  eval $cmd
  echo "Testing Sets Combined."
fi

if [ $STEP_SUBSET_AM_DATA -eq 1 ]; then
  # trn set
  utils/subset_data_dir.sh data/train_all $num_utts_gmm data/train_gmm
  utils/subset_data_dir.sh data/train_all $num_utts_dnn data/train    # For DNN training

  # tst set
  utils/subset_data_dir.sh data/test_all $num_utts_test data/test1
  utils/subset_data_dir.sh data/test_all $num_utts_test data/test2
fi

if [ $STEP_PREP_LANG -eq 1 ]; then
  utils/prepare_lang.sh --position-dependent-phones false \
    data/local/dict "<UNK>" data/local/lang data/lang || exit 1;
fi

if [ $STEP_TRAIN_LM -eq 1 ]; then
  dir=data/local/lm
  mkdir -p $dir

  # text normalization
  python3 local/cn_tn.py --to_upper $lm_text $dir/tmp

  # word segmentation
  python3 local/cn_ws.py data/local/dict/ws_vocab.txt $dir/tmp $dir/text  || exit 1;

  # train arpa
  local/train_arpa.sh data/local/dict/lexicon.txt $dir/text $dir || exit 1;

  # convert LM to FST format
  utils/format_lm.sh data/lang data/local/lm/3gram-mincount/lm_unpruned.gz \
    data/local/dict/lexicon.txt data/lang_test || exit 1;
fi

if [ $STEP_TRAIN_GMM -eq 1 ]; then
  local/run_gmm.sh --nj $nj \
    --stage $gmm_stage \
    --train-set "train_gmm" --test-sets "test1 test2"
fi

if [ $STEP_TRAIN_DNN -eq 1 ]; then
  local/chain/run_tdnn.sh --nj $nj \
    --stage $dnn_stage \
    --train-set "train" --test-sets "test1 test2"
fi

if [ $STEP_SHOW_RESULTS -eq 1 ]; then
  local/show_results.sh
fi

exit 0;
