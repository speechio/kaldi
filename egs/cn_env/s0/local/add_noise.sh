#!/bin/sh

normalize_output=false
background_mode=true
random_noise_position=true
append_suffix=""
append_snr=false

. ./path.sh
. ./utils/parse_options.sh

if [ $# -ne 5 ]; then
    echo "add_noise.sh <wav.list/wav.scp> <noise.list> <snr_lower> <snr_upper> <dest_dir>"
    echo "  --append-snr false(default)"
    echo "  --append-suffix ''(default)"
    echo "  --normalize-output false(default)"
    echo "  --background-mode true(default)"
    echo "  --random-noise-position true(default)"
    echo "e.g: add_noise.sh wav.list noise.list 0 10 wdir"
    echo "e.g: add_noise.sh --scp true wav.scp noise.list 0 10 wdir"
    exit 1;
fi

wavs=$1
noise_list=$2
snr_lower=$3
snr_upper=$4
dir=$5

n=1
NF=`awk '{print NF}' $wavs | sort -nu | tail -n 1`

mkdir -p $dir
opts="--background-mode=$background_mode --normalize-output=$normalize_output --random-noise-position=$random_noise_position"

while read l; do
    if [ $NF -eq 1 ]; then 
        # wav.list
        f=$l
        filename=`basename $f`
        key="${filename%.*}"
        ext="${filename##*.}"
    elif [ $NF -eq 2 ]; then 
        # wav.scp
        key=`echo $l | awk '{print $1}'`
        f=`echo $l | awk '{print $2}'`
        filename=`basename $f`
        ext="${filename##*.}"
    else
        echo "Error: unknown format, need wav.list or wav.scp"
        exit 1
    fi

    if [ ! -z "$append_suffix" ]; then
        key="${key}__${append_suffix}"
    fi
    
    noise=`shuf $noise_list | head -n 1`
    snr=`seq ${snr_lower} ${snr_upper} | shuf | head -n 1`

    if [ "$append_snr" = "true" ]; then
        snr_str="SNR${snr}dB"
        key="${key}__${snr_str}"
    fi

    o=${key}.${ext}
    echo -e "$n\t${key}\t$dir/$o\tsnr:$snr\tnoise:$noise"
    wav-reverberate $opts --additive-signals="$noise" --snrs="$snr" --start-times=0 $f $dir/$o
    n=$((n+1))
done < $wavs

