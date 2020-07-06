mode=
. utils/parse_options.sh

if [ $# -ne 3 ]; then
    echo "arpa2fst.sh --mode=fst   <G.arpa> <words.txt> <Gr.fst>"
    echo "arpa2fst.sh --mode=carpa <G.arpa> <words.txt> <G.carpa>"
    exit 1;
fi

. ./path.sh

arpa=$1
vocab=$2
output=$3


if [ $mode = "fst" ]; then
    arpa2fst --disambig-symbol=#0 --read-symbol-table=$vocab $arpa - \
      | fstproject --project_output=true - \
      | fstarcsort --sort_type=ilabel \
      > $output
elif [ $mode = "carpa" ]; then
    unk=`grep '<unk>' $vocab | awk '{print $2}'`
    bos=`grep '<s>'   $vocab | awk '{print $2}'`
    eos=`grep '</s>'  $vocab | awk '{print $2}'`
    #arpa-to-const-arpa --bos-symbol=$bos --eos-symbol=$eos --unk-symbol=$unk "cat $arpa | utils/map_arpa_lm.pl $vocab|" $output
    arpa-to-const-arpa --bos-symbol=$bos --eos-symbol=$eos --unk-symbol=$unk $arpa $output
fi

echo "Rescore graph done."
