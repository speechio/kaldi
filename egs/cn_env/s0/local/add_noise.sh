#!/bin/sh
if [ $# -ne 5 ]; then
    echo "add_noise.sh <wav.list> <noise.list> <snr_lower> <snr_upper> <working_dir>"
    echo "  --normalize-output false(default)"
    echo "  --background-mode true(default)"
    echo "  --random-noise-position true(default)"
    echo "e.g: add_noise.sh wav.list noise.list 0 10 wdir"
    exit 1;
fi

normalize_output=false
background_mode=true
random_noise_position=true

. ./path.sh
. ./utils/parse_options.sh

wav_list=$1
noise_list=$2
snr_lower=$3
snr_upper=$4
dir=$5

mkdir -p $dir
for f in `cat $wav_list`; do
    noise=`shuf $noise_list | head -n 1`
    snr=`seq ${snr_lower} ${snr_upper} | shuf | head -n 1`
    iname=`basename $f`
    oname=SNR${snr}_$iname
    echo "adding noise: $noise to audio: $f with snr: $snr, destination:$dir/$oname"
    wav-reverberate \
        --background-mode=$background_mode --normalize-output=$normalize_output \
        --additive-signals="$noise" --snrs="$snr" --random-noise-position=$random_noise_position \
        --start-times="0" \
        $f $dir/$oname
done

