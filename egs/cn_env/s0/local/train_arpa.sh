#!/bin/bash
# Copyright 2019 Jiayu DU

. ./path.sh
. ./utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "train_arpa.sh <lexicon> <word-segmented-text> <dir>"
  echo " e.g train_arpa.sh data/local/dict/lexicon.txt prepare/ws_text.txt data/local/lm"
  exit 1;
fi

lexicon=$1
itext=$2
dir=$3

for f in "$text" "$lexicon"; do
  [ ! -f $x ] && echo "$0: No such file $f" && exit 1;
done

kaldi_lm=`which train_lm.sh`
if [ -z $kaldi_lm ]; then
  echo "$0: train_lm.sh is not found. That might mean it's not installed"
  echo "$0: or it is not added to PATH"
  echo "$0: Use the script tools/extras/install_kaldi_lm.sh to install it"
  exit 1
fi

mkdir -p $dir
cleantext=$dir/text.no_oov

# map OOV to <UNK>
cat $itext | awk -v lex=$lexicon 'BEGIN{while((getline<lex) >0){ seen[$1]=1; } }
  {for(n=1; n<=NF;n++) {  if (seen[$n]) { printf("%s ", $n); } else {printf("<UNK> ");} } printf("\n");}' \
  > $cleantext || exit 1;

# Get word counts from text corpus
cat $cleantext | awk '{for(n=1;n<=NF;n++) print $n; }' | \
  sort | uniq -c | sort -nr > $dir/word.counts || exit 1;

# add one-count for each word in the lexicon
# (but not silence, we don't want it in the LM-- we'll add it optionally later).
cat $cleantext | awk '{for(n=1;n<=NF;n++) print $n; }' | \
  cat - <(grep -w -v '!SIL' $lexicon | awk '{print $1}') | \
  sort | uniq -c | sort -nr > $dir/unigram.counts || exit 1;

# translate text into concise form, store the translation in word_map
cat $dir/unigram.counts  | awk '{print $2}' | get_word_map.pl "<s>" "</s>" "<UNK>" > $dir/word_map || exit 1;
cat $cleantext | awk -v wmap=$dir/word_map 'BEGIN{while((getline<wmap)>0)map[$1]=$2;}
  { for(n=1;n<=NF;n++) { printf map[$n]; if(n<NF){ printf " "; } else { print ""; }}}' |\
  gzip -c >$dir/train.gz || exit 1;

train_lm.sh --arpa --lmtype 3gram-mincount $dir || exit 1;

# note: output is data/local/lm/3gram-mincount/lm_unpruned.gz

echo "local/train_arpa.sh succeeded"
exit 0


# From here is some commands to do a baseline with SRILM (assuming
# you have it installed).
heldout_sent=10000 # Don't change this if you want result to be comparable with
    # kaldi_lm results
sdir=$dir/srilm # in case we want to use SRILM to double-check perplexities.
mkdir -p $sdir
cat $cleantext | awk '{for(n=1;n<=NF;n++){ printf $n; if(n<NF) printf " "; else print ""; }}' | \
  head -$heldout_sent > $sdir/heldout
cat $cleantext | awk '{for(n=1;n<=NF;n++){ printf $n; if(n<NF) printf " "; else print ""; }}' | \
  tail -n +$heldout_sent > $sdir/train

cat $dir/word_map | awk '{print $1}' | cat - <(echo "<s>"; echo "</s>" ) > $sdir/wordlist

ngram-count -text $sdir/train -order 3 -limit-vocab -vocab $sdir/wordlist -unk \
  -map-unk "<UNK>" -kndiscount -interpolate -lm $sdir/srilm.o3g.kn.gz
ngram -lm $sdir/srilm.o3g.kn.gz -ppl $sdir/heldout

# Note: perplexity SRILM gives to Kaldi-LM model is same as kaldi-lm reports above.
# Difference in WSJ must have been due to different treatment of <UNK>.
ngram -lm $dir/3gram-mincount/lm_unpruned.gz  -ppl $sdir/heldout

echo "local/train_lms.sh succeeded"
exit 0
