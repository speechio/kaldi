if [ $# != 1 ]; then
  echo "Usage: $0 <new-dir>"
  echo " $0 s6"
  exit 1;
fi

dir=$1

mkdir -p $dir

file_list='cmd.sh path.sh run.sh'
dir_list='conf local'

cd $dir

for f in $file_list; do
    cp ../s0/$f .
done

for d in $dir_list; do
    ln -s ../s0/$d $d
done

ln -s ../../wsj/s5/steps steps
ln -s ../../wsj/s5/utils utils
cd -
