#!/bin/sh

nj=1
stage=1
debug=2
mode=

. ./path.sh
. ./utils/parse_options.sh


if [ $# -ne 5 ]; then
    echo "arpa.sh --mode <mode> [--nj <nj>] <arpa> <ngram-order> <words.txt> <text> <working_dir>"
    echo "  --mode: train / test / prune (no default, must specified explicitly"
    echo "  --nj 1(default)"
    echo "  --stage: 1(tn&ws processing) 2(train/test/prune)"
    echo "  <words.txt> word-table from kaldi"
    echo "  For training: arpa.sh --mode train --nj 10 4gram.arpa 4 words.txt trn.txt wdir"
    echo "  For testing : arpa.sh --mode test  --nj 1  4gram.arpa 4 words.txt tst.txt wdir"
    echo "  For pruning : arpa.sh --mode prune --nj 1  4gram.arpa 4 words.txt tst.txt wdir"
    echo "  Be carefull, existing <working_dir> will be deleted."
    exit 1;
fi

arpa=$1
order=$2
vocab=$3
text=$4
dir=$5

thresholds="1e-8 1e-9 1e-10 1e-11 1e-12"
#thresholds="1e-5 1e-6 1e-7"

echo "`basename $0`: counting lines ..."
n=`cat $text | wc -l`
echo "`basename $0`: $n lines in $text"

[ -d $dir ] && rm -rf $dir
mkdir -p $dir
text_name=`basename $text`
processed_text=$text

if [ $stage -le 1 ]; then
    cat $vocab | grep -v '<eps>' | grep -v '#0' | awk '{print $1, 99}' > $dir/jieba.vocab

    if [ $nj -eq 1 ]; then
        echo "TN..."
        local/cn_tn.py --to_upper $text $dir/${text_name}.tn
        echo "TN done."

        echo "WS..."
        local/cn_ws.py $dir/jieba.vocab $dir/${text_name}.tn $dir/${text_name}.tn.ws
        echo "WS done."
    else
        # parallel tn & ws
        echo "TN..."
        split -n l/${nj} $text $dir/${text_name}_
        for f in `ls $dir/${text_name}_*`; do
            local/cn_tn.py --to_upper $f ${f}.tn >& ${f}.tn.log &
        done
        wait
        echo "TN done."
    
        echo "WS..."
        for f in `ls $dir/${text_name}_*.tn`; do
            local/cn_ws.py $dir/jieba.vocab $f ${f}.ws >& ${f}.ws.log &
        done
        wait
        echo "WS done."
    
        echo "Merging..."
        cat /dev/null > $dir/${text_name}.tn.ws
        for f in `ls $dir/${text_name}_*.tn.ws`; do
            cat $f >> $dir/${text_name}.tn.ws
        done
        echo "Merging done."
    fi

    processed_text=$dir/${text_name}.tn.ws
    echo "Processed text: $processed_text"
fi

if [ $stage -le 2 ]; then
    if [ $mode == "train" ]; then
        echo "Training..."

        command -v ngram-count 1>/dev/null 2>&1 || { echo "Error: make sure your PATH can find SRILM's binaries"; exit 1; }
        [ -f $arpa ] && echo "WARNING: $arpa existed, overwriting."

        cat $vocab | grep -v '<eps>' | grep -v '#0' | awk '{print $1}' > $dir/ngram.vocab
        ## single process training
        ngram-count -text $processed_text \
            -order $order -lm $arpa \
            -limit-vocab -vocab $dir/ngram.vocab \
            -unk -map-unk "<UNK>" \
            -kndiscount -interpolate \
            -debug $debug

        ## use this branch if you have large enough memory for parallel counting
        #mkdir -p $dir/{splits,counts,merge}

        #split -l 1000000 $dir/${text_name}.tn.ws $dir/splits/

        #ls $dir/splits/* > $dir/splits.list
        #$SRILM_SCRIPT/make-batch-counts $dir/splits.list 3 cat $dir/counts \
        #    -order $order -limit-vocab -vocab $dir/ngram.vocab 

        #ls $dir/counts/*.gz > $dir/counts.list
        #$SRILM_SCRIPT/merge-batch-counts $dir/merge $dir/counts.list

        #$SRILM_SCRIPT/make-big-lm -read $dir/merge/*.gz \
        #    -order $order -limit-vocab -vocab $dir/ngram.vocab \
        #    -kndiscount -interpolate \
        #    -lm $arpa

        echo "Training done, $arpa."

    elif [ $mode == "test" ]; then
        echo "Testing..."

        command -v ngram 1>/dev/null 2>&1 || { echo "Error: make sure your PATH can find SRILM's binaries"; exit 1; }
        [ ! -f $arpa ] && { echo "Error: $arpa no such file"; exit 1; }

        ngram -debug $debug -order $order -lm $arpa -ppl $processed_text > $dir/PPL

        tail -n 1 $dir/PPL
        echo "Testing done, $processed_text on $arpa."

    elif [ $mode == "prune" ]; then
        echo "Pruning ... "

        command -v ngram 1>/dev/null 2>&1 || { echo "Error: make sure your PATH can find SRILM's binaries"; exit 1; }
        [ ! -f $arpa ] && { echo "Error: $arpa no such file"; exit 1; }

        for x in $thresholds; do
            model=$dir/prune${x}.`basename $arpa`
            ngram -debug $debug -order $order -lm $arpa -prune $x -write-lm $model >& $dir/prune${x}.log &
        done
        wait

        echo "Start tesing pruned models"
        echo "----------------"
        ngram -debug $debug -order $order -lm $arpa -ppl $processed_text > $dir/raw.ppl
        du -h $arpa; echo -n "$dir/raw.ppl: "; tail -n 1 $dir/raw.ppl

        for x in $thresholds; do
            echo "----------------"
            model=$dir/prune${x}.`basename $arpa`
            ppl=$dir/prune${x}.ppl
            ngram -debug $debug -order $order -lm $model -ppl $processed_text > $ppl
            du -h $model; echo -n "$ppl:"; tail -n 1 $ppl;
        done
    else
        echo "unsupported mode: $mode"
        exit 0
    fi
fi

