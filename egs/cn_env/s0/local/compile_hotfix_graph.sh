
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

name=`basename $hotfix_list .list`

cat $vocab | grep -v '<eps>' | grep -v '#0' | grep -v '<unk>' | grep -v '<UNK>' | grep -v '<s>' | grep -v '</s>' | awk '{print $1, 99}' > $dir/jieba.vocab

# here the "--has_key" actually skip the hotfix weight field
python3 local/cn_ws.py --has_key $dir/jieba.vocab $hotfix_list $dir/${name}_ws.list

utils/sym2int.pl --map-oov "<unk>" -f 2- $vocab $dir/${name}_ws.list > $dir/${name}_int.list

