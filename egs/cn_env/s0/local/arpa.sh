#!/bin/sh
if [ $# -ne 5 ] && [ $# -ne 6 ]; then
    echo "arpa.sh <arpa> <ngram-order> <words.txt> <text> <working_dir> [PPL]"
    echo "  words.txt is word table from kaldi"
    echo "  For training: arpa.sh 3gram.arpa 3 words.txt text.txt tmp"
    echo "  For testing : arpa.sh 3gram.arpa 3 words.txt text.txt tmp PPL"
    exit 1;
fi


arpa=$1
order=$2
vocab=$3
text=$4
dir=$5

mode=
if [ $# -eq 5 ]; then
    mode=train
elif [ $# -eq 6 ]; then
    mode=test
    PPL=$6
fi

nj=45
stage=0
debug=2

mkdir -p $dir
text_name=`basename $text`

echo "`basename $0`: counting number of lines in <text>"
n=`cat $text | wc -l`
echo "`basename $0`: $n lines"

cat $vocab | grep -v '<eps>' | grep -v '#0' | awk '{print $1, 99}' > $dir/jieba.vocab
if [ $n -lt 100 ]; then
    # TN
    if [ $stage -le 1 ]; then
        local/cn_tn.py --to_upper $text $dir/${text_name}.tn
    fi
    
    # WS
    if [ $stage -le 2 ]; then
        local/cn_ws.py $dir/jieba.vocab $dir/${text_name}.tn $dir/${text_name}.tn.ws
    fi
else
    split -n l/${nj} $text $dir/${text_name}_
    for f in `ls $dir/${text_name}_*`; do
        local/cn_tn.py --to_upper $f ${f}.tn >& ${f}.tn.log &
    done
    wait

    for f in `ls $dir/${text_name}_*.tn`; do
        local/cn_ws.py $dir/jieba.vocab $f ${f}.ws >& ${f}.ws.log &
    done
    wait

    cat /dev/null > $dir/${text_name}.tn.ws
    for f in `ls $dir/${text_name}_*.tn.ws`; do
        cat $f >> $dir/${text_name}.tn.ws
    done
fi

if [ $stage -le 3 ]; then
    if [ $mode == "train" ]; then
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

        echo "training done, $arpa."
    elif [ $mode == "test" ]; then
        command -v ngram 1>/dev/null 2>&1 || { echo "Error: make sure your PATH can find SRILM's binaries"; exit 1; }
        if [ ! -f $arpa ]; then
            echo "$arpa no such file"
            exit 0
        fi

        ngram -debug $debug -order $order -lm $arpa -ppl $dir/${text_name}.tn.ws > $PPL

        tail -n 1 $PPL
        echo "testing done, $text on $arpa."
    fi
fi

