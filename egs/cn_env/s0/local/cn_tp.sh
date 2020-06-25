#!/bin/sh

nj=1

. ./path.sh
. ./utils/parse_options.sh

# CN Text Processing
if [ $# -ne 3 ]; then
    echo "cn_tp.sh [--nj <nj>] [--stage <stage>] <vocab.txt> <text.txt> <working_dir>"
    exit 1;
fi

vocab=$1
text=$2
dir=$3

name=`basename $text .txt`
new_text=${name}_tn_ws.txt

mkdir -p $dir

cat $vocab | grep -v '<eps>' | grep -v '#0' | grep -v '<unk>' | grep -v '<UNK>' | grep -v '<s>' | grep -v '</s>' | awk '{print $1, 99}' > $dir/jieba.vocab

if [ $nj -eq 1 ]; then
    echo "TN..."
    local/cn_tn.py --to_upper $text $dir/${name}_tn
    echo "TN done."

    echo "WS..."
    local/cn_ws.py $dir/jieba.vocab $dir/${name}_tn $dir/${new_text}
    echo "WS done."
else
    # parallel tn & ws
    echo "TN..."
    split -n l/${nj} $text $dir/${name}_
    for f in `ls $dir/${name}_*`; do
        local/cn_tn.py --to_upper $f ${f}_tn >& ${f}_tn.log &
    done
    wait
    echo "TN done."

    echo "WS..."
    for f in `ls $dir/${name}_*_tn`; do
        local/cn_ws.py $dir/jieba.vocab $f ${f}_ws >& ${f}_ws.log &
    done
    wait
    echo "WS done."

    echo "Merging..."
    cat /dev/null > $dir/${new_text}
    for f in `ls $dir/${name}_*_tn_ws`; do
        cat $f >> $dir/${new_text}
    done
    echo "Merging done."
fi
