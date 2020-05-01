#!/bin/bash

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

corpus=/data/text/CLUECorpus2020
find $corpus -name "*.txt" >  list
n=`cat list | wc -l`
m=28698 #total m=28698
echo $m, $n

task=CLUE2020_${m}
trn=${task}_trn.txt
tst=test_corpus/tst.txt

cat /dev/null > $trn
for f in `shuf list | head -n $m`; do 
    cat $f >> $trn;
done

sh local/arpa.sh --mode train --nj 46 \
    ${task}_4gram.arpa 4 words.txt $trn ${task}_trn


sh local/arpa.sh --mode test \
    ${task}_4gram.arpa 4 words.txt $tst ${task}_tst

sh local/arpa.sh --mode prune \
    ${task}_4gram.arpa 4 words.txt $tst ${task}_prune0
