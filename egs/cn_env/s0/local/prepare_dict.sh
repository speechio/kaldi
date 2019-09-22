#!/bin/bash
# Copyright  2019 Jiayu DU

. ./path.sh

raw_lexicon=
dir=data/local/dict

if [ $# -ne 2 ]; then
  echo "Usage: $0 <raw-lexicon> <target-dir>";
  exit 1;
fi

raw_lexicon=$1
dir=$2

# here we map <UNK> to the phone spn(spoken noise)
mkdir -p $dir
cp $raw_lexicon $dir/lexicon.txt
echo -e "<UNK>\tspn" >> $dir/lexicon.txt

# prepare silence_phones.txt, nonsilence_phones.txt, optional_silence.txt, extra_questions.txt
cat $dir/lexicon.txt | awk '{ for(n=2;n<=NF;n++){ phones[$n] = 1; }} END{for (p in phones) print p;}'| \
  perl -e 'while(<>){ chomp($_); $phone = $_; next if ($phone eq "sil");
    m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$1} .= "$phone "; }
    foreach $l (values %q) {print "$l\n";}
  ' | sort -k1 > $dir/nonsilence_phones.txt  || exit 1;

echo sil > $dir/silence_phones.txt
echo sil > $dir/optional_silence.txt

cat $dir/silence_phones.txt | awk '{printf("%s ", $1);} END{printf "\n";}' > $dir/extra_questions.txt || exit 1;
cat $dir/nonsilence_phones.txt | perl -e 'while(<>){ foreach $p (split(" ", $_)) {
  $p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; if($p eq "\$0"){$q{""} .= "$p ";}else{$q{$2} .= "$p ";} } } foreach $l (values %q) {print "$l\n";}' \
 >> $dir/extra_questions.txt || exit 1;

echo "local/prepare_dict.sh succeeded"
exit 0;
