
. utils/parse_options.sh

if [ $# -ne 3 ]; then
    echo "compile_hotfix_graph.sh <hotfix.list> <words.txt> <wdir>"
    exit 1;
fi

. ./path.sh

hotfix_list=$1
vocab=$2
dir=$3

mkdir -p $dir

name=`basename $hotfix_list .txt`

# here the "--has_key" actually skip the hotfix weight field
sh local/cn_tp.sh --has_key true $vocab $hotfix_list $dir

utils/sym2int.pl --map-oov "<unk>" -f 2- $vocab $dir/${name}_tn_ws.txt > $dir/${name}_int.txt

compile-hotfix-graph $dir/${name}_int.txt $dir/${name}.bin $dir/${name}.dot

