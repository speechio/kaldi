#!/bin/bash

. ./path.sh
. ./cmd.sh

if [ "$#" -ne 2 ]; then
    echo "$0 arpa am_dir"
    echo "e.g.: $0 story.arpa exp/chain/tdnnf_1a"
    echo "  will build 4gram.arpa into a new dir: exp/chain/tdnnf_1a/graph_story/HCLG.fst"
    exit 0;
fi

arpa=$1
am_dir=$2

[ ! -d data/lang_test ] && { echo "ERROR: cannot find data/lang_test dir as raw template, check pwd please"; exit 1; }
[ ! -f $1 ] && { echo "ERROR: cannot find arpa $1"; exit 1; }
[ ! -d $2 ] && { echo "ERROR: cannot find acoustic model dir $2"; exit 1; }

name=`basename $1 '.arpa'`
new_lang=$am_dir/lang_test_${name}
new_graph=$am_dir/graph_${name}
echo "building new arpa:$arpa into new HCLG in $new_graph"

cp -r data/lang_test $new_lang
rm ${new_lang}/G.fst
sed -i "s:<UNK>:<unk>:g" $new_lang/words.txt
arpa2fst --disambig-symbol=#0 --read-symbol-table=${new_lang}/words.txt $arpa ${new_lang}/G.fst
utils/mkgraph.sh --self-loop-scale 1.0 $new_lang $am_dir $new_graph

echo "$0: Done building decoding graph in $new_graph"
