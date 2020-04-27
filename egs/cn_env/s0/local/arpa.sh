#!/bin/sh

nj=1
stage=0
debug=2
mode=

. path.sh
. utils/parse_options.sh

if [ $# -ne 5 ] && [ $# -ne 6 ]; then
    echo "arpa.sh --mode train/test [--nj <nj>] <arpa> <ngram-order> <words.txt> <text> <working_dir> [PPL]"
    echo "  --nj default 1"
    echo "  <words.txt> word-table from kaldi"
    echo "  For training: arpa.sh --mode train --nj 10 3gram.arpa 3 words.txt text.txt tmp"
    echo "  For testing : arpa.sh --mode test 3gram.arpa 3 words.txt text.txt tmp PPL"
    exit 1;
fi

arpa=$1
order=$2
vocab=$3
text=$4
dir=$5
PPL=
if [ $# -eq 6 ]; then
    PPL=$6
fi

echo "`basename $0`: counting lines ..."
n=`cat $text | wc -l`
echo "`basename $0`: $n lines in $text"

mkdir -p $dir
text_name=`basename $text`

if [ $stage -le 0 ]; then
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
fi

if [ $stage -le 1 ]; then
    if [ $mode == "train" ]; then
        echo "Training..."
        command -v ngram-count 1>/dev/null 2>&1 || { echo "Error: make sure your PATH can find SRILM's binaries"; exit 1; }
        if [ -f $arpa ]; then
            echo "WARNING: $arpa existed, overwriting."
        fi
        cat $vocab | grep -v '<eps>' | grep -v '#0' | awk '{print $1}' > $dir/ngram.vocab
        ## single process training
        ngram-count -text $dir/${text_name}.tn.ws \
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
        if [ ! -f $arpa ]; then
            echo "$arpa no such file"
            exit 0
        fi

        ngram -debug $debug -order $order -lm $arpa -ppl $dir/${text_name}.tn.ws > $PPL

        tail -n 1 $PPL
        echo "Testing done, $text on $arpa."
    fi
fi

