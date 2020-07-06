if [ $# -ne 3 ]; then
    echo "arpa2fst.sh <G.arpa> <words.txt> <Gr.fst>"
    exit 1;
fi

. ./path.sh

arpa=$1
vocab=$2
fst=$3

arpa2fst --disambig-symbol=#0 --read-symbol-table=$vocab $arpa - \
      | fstproject --project_output=true - \
      | fstarcsort --sort_type=ilabel \
      > $fst
