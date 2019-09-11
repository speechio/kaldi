#!/bin/bash
# Copyright  2019 Jiayu DU

. ./path.sh || exit 1;

tmp=
dir=

if [ $# != 4 ]; then
  echo "Usage: $0 <corpus-data-dir> <word-seg-vocab> <tmp-dir> <output-dir>"
  echo " $0 /export/AISHELL-2/iOS/train data/local/dict/word_seg_vocab.txt data/local/train data/train"
  exit 1;
fi

corpus=$1
word_seg_vocab=$2
tmp=$3
dir=$4

echo "prepare_data.sh: Preparing data in $corpus"

mkdir -p $tmp
mkdir -p $dir

# corpus check
if [ ! -d $corpus ] || [ ! -f $corpus/wav.scp ] || [ ! -f $corpus/trans.txt ]; then
  echo "Error: $0 requires wav.scp and trans.txt under $corpus directory."
  exit 1;
fi

# validate utt-key list
awk '{print $1}' $corpus/wav.scp   > $tmp/wav_utt.list
awk '{print $1}' $corpus/trans.txt > $tmp/trans_utt.list
utils/filter_scp.pl -f 1 $tmp/wav_utt.list $tmp/trans_utt.list > $tmp/utt.list

# wav.scp
awk -F'\t' -v path_prefix=$corpus '{printf("%s\t%s/%s\n",$1,path_prefix,$2)}' $corpus/wav.scp > $tmp/tmp_wav.scp
utils/filter_scp.pl -f 1 $tmp/utt.list $tmp/tmp_wav.scp | sort -k 1 | uniq > $tmp/wav.scp

# text (word-segmentation)
utils/filter_scp.pl -f 1 $tmp/utt.list $corpus/trans.txt | sort -k 1 | uniq > $tmp/trans.txt
python -c "import jieba" 2>/dev/null || \
  (echo "jieba is not found. Use tools/extra/install_jieba.sh to install it." && exit 1;)
python local/word_segmentation.py --has_key $word_seg_vocab $tmp/trans.txt $tmp/text

# utt2spk & spk2utt
awk -F'\t' '{print $2}' $tmp/wav.scp > $tmp/wav.list
sed -e 's:\.wav::g' $tmp/wav.list | \
  awk -F'/' '{i=NF-1;printf("%s\t%s\n",$NF,$i)}' > $tmp/tmp_utt2spk
utils/filter_scp.pl -f 1 $tmp/utt.list $tmp/tmp_utt2spk | sort -k 1 | uniq > $tmp/utt2spk
utils/utt2spk_to_spk2utt.pl $tmp/utt2spk | sort -k 1 | uniq > $tmp/spk2utt

# copy prepared resources from tmp_dir to target dir
mkdir -p $dir
for f in wav.scp text spk2utt utt2spk; do
  cp $tmp/$f $dir/$f || exit 1;
done

echo "local/prepare_data.sh succeeded"
exit 0;
