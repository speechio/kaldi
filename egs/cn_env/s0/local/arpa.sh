#!/bin/sh

if [ $# -ne 5 ]; then
    echo "arpa.sh <mode> <words.txt> <text> <lm-order> <lm.arpa>"
    echo "  mode = train or test"
    echo "  words.txt is word table from kaldi"
    echo "  e.g.: arpa.sh train words.txt text.txt 3 lm3.arpa"
    echo "  e.g.: arpa.sh test words.txt text.txt 3 lm3.arpa"
    exit 1;
fi

#---
SRILM_BIN=/home/dophist/work/git/srilm-1.7.2/bin/i686-m64
SRILM_SCRIPT=/home/dophist/work/git/srilm-1.7.2/bin
KENLM_ROOT=/home/dophist/work/git/kenlm

export PATH=$PATH:$SRILM_BIN:$SRILM_SCRIPT

mode=$1
vocab=$2
text=$3
order=$4
arpa=$5

stage=0
debug=2

dir="lmdir"

mkdir -p $dir
text_name=`basename $text`

# TN
if [ $stage -le 1 ]; then
    local/cn_tn.py --to_upper $text $dir/${text_name}.tn
fi

# WS
if [ $stage -le 2 ]; then
    cat $vocab | grep -v '<eps>' | grep -v '<UNK>'| grep -v '#0' | awk '{print $1, 99}' > $dir/jieba.vocab
    local/cn_ws.py $dir/jieba.vocab $dir/${text_name}.tn $dir/${text_name}.tn.ws
fi

# train or test arpa
if [ $stage -le 3 ]; then
    if [ $mode == "train" ]; then
        if [ -f $arpa ]; then
            echo "WARNING: $arpa existed, overwriting."
        fi
        cat $vocab | grep -v '<eps>' | grep -v '<UNK>'| grep -v '#0' | awk '{print $1}' > $dir/ngram.vocab
        ## small LM
        #${SRILM_BIN}/ngram-count -debug $debug -order $order -limit-vocab -vocab $dir/ngram.vocab -kndiscount -interpolate -text $dir/${text_name}.tn.ws -lm $arpa.single

        # big LM
        mkdir -p $dir/{splits,counts,merge}

        split -l 100000 $dir/${text_name}.tn.ws $dir/splits/

        ls $dir/splits/* > $dir/splits.list
        $SRILM_SCRIPT/make-batch-counts $dir/splits.list 3 cat $dir/counts \
            -order $order -limit-vocab -vocab $dir/ngram.vocab 

        ls $dir/counts/*.gz > $dir/counts.list
        $SRILM_SCRIPT/merge-batch-counts $dir/merge $dir/counts.list

        $SRILM_SCRIPT/make-big-lm -read $dir/merge/*.gz \
            -order $order -limit-vocab -vocab $dir/ngram.vocab \
            -kndiscount -interpolate \
            -lm $arpa

        echo "training done, $arpa."
    else
        if [ ! -f $arpa ]; then
            echo "$arpa no such file"
            exit 0
        fi
        ${SRILM_BIN}/ngram -debug $debug -order $order -lm $arpa -vocab $dir/ngram.vocab -limit-vocab -ppl $dir/${text_name}.tn.ws > $dir/PPL
        echo "testing done, $text."
    fi
fi

