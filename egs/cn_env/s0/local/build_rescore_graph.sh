#!/bin/bash

mode=
. utils/parse_options.sh

if [ $# -ne 2 ] && [ $# -ne 3 ]; then
    echo "compile_rescore_graph.sh --mode fst   <G.arpa> <words.txt> <Gp.fst>"
    echo "compile_rescore_graph.sh --mode carpa <G.arpa> <words.txt> <G.carpa>"
    echo "compile_rescore_graph.sh --mode kenlm <G.arpa> <G.kenlm>"
    exit 1;
fi

. ./path.sh


if [ $mode = "fst" ]; then
    arpa=$1
    vocab=words_unk.txt
    output=$3

    # convert <UNK> (in kaldi training symbol table) to arpa's <unk>
    sed "s:<UNK>:<unk>:g" $2 > $vocab

    arpa2fst --disambig-symbol=#0 --read-symbol-table=$vocab $arpa - \
      | fstproject --project_output=true - \
      | fstarcsort --sort_type=ilabel \
      > $output

elif [ $mode = "carpa" ]; then
    arpa=$1
    vocab=words_unk.txt
    output=$3

    # convert <UNK> (in kaldi training symbol table) to arpa's <unk>
    sed "s:<UNK>:<unk>:g" $2 > $vocab

    unk=`grep '<unk>' $vocab | awk '{print $2}'`
    bos=`grep '<s>'   $vocab | awk '{print $2}'`
    eos=`grep '</s>'  $vocab | awk '{print $2}'`
    arpa-to-const-arpa --bos-symbol=$bos --eos-symbol=$eos --unk-symbol=$unk "cat $arpa | utils/map_arpa_lm.pl $vocab|" $output

elif [ $mode = "kenlm" ]; then
    arpa=$1
    output=$2

    ken_opts=""
    #ken_opts="-q 8 -b 8"
    #ken_opts="-q 8 -b 8 -a 255"

    build_binary $ken_opts trie $arpa $output
fi

echo "$0: compiling rescore graph done: $output"

