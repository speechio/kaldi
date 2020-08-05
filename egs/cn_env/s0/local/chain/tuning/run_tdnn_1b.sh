#!/bin/bash
# _1b is as _1a, with dropout & some hyperparam tuning, based on multi_en run_tdnn_5b.sh

set -e

# config
dir=exp/chain/tdnn_1b
affix=job_4_4_lr_0.001_0.00005

nj=20
train_set="train"
test_sets="test"
decode_iter=

stage=0
train_stage=-10
get_egs_stage=-10
cmvn_opts="--norm-means=false --norm-vars=false"

# training options
num_epochs=4
frames_per_iter=1500000
num_chunk_per_minibatch=128
frames_per_eg=150,110,90

num_jobs_initial=4
num_jobs_final=4
initial_effective_lrate=0.001
final_effective_lrate=0.00005

dropout_schedule='0,0@0.20,0.5@0.50,0'
l2_regularize=0.00005
max_param_change=2.0
leaky_hmm_coefficient=0.1
xent_regularize=0.1

remove_egs=true
common_egs_dir=

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

# we use 40-dim high-resolution mfcc features (w/o pitch and ivector) for nn training
# no utt- and spk- level cmvn

dir=${dir}${affix:+_$affix}
ali_dir=exp/tri3_ali
lat_dir=exp/tri3_lat_ali
tree_dir=exp/chain/tree
lang=data/lang_chain

if [ $stage -le 6 ]; then
  for x in ${train_set} ${test_sets}; do
    utils/copy_data_dir.sh data/${x} data/mfcc_hires_${x}

    utils/data/perturb_data_dir_volume.sh data/mfcc_hires_${x} || exit 1;

    steps/make_mfcc.sh --cmd "$train_cmd" --nj $nj \
      --mfcc-config conf/mfcc_hires.conf \
      data/mfcc_hires_${x} data/mfcc_hires_${x}/log mfcc_hires || exit 1;

    steps/compute_cmvn_stats.sh \
      data/mfcc_hires_${x} data/mfcc_hires_${x}/log mfcc_hires || exit 1;

    utils/fix_data_dir.sh data/mfcc_hires_${x} || exit 1;
  done
fi

if [ $stage -le 7 ]; then
    # get alignments for DNN training
  steps/make_mfcc_pitch.sh --cmd "$train_cmd" --nj $nj \
    --pitch-config conf/pitch.conf \
    data/${train_set} data/${train_set}/log mfcc || exit 1;

  steps/compute_cmvn_stats.sh \
    data/${train_set} data/${train_set}/log mfcc || exit 1;

  utils/fix_data_dir.sh data/${train_set} || exit 1;

  steps/align_si.sh --cmd "$train_cmd" --nj $nj \
    data/${train_set} data/lang exp/tri3 $ali_dir || exit 1;
fi

if [ $stage -le 7 ]; then
  # Get the alignments as lattices (gives the LF-MMI training more freedom).
  # use the same num-jobs as the alignments
  nj=$(cat $ali_dir/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh --cmd "$train_cmd" --nj $nj \
    data/$train_set data/lang exp/tri3 $lat_dir
  rm ${lat_dir}/fsts.*.gz # save space
fi

if [ $stage -le 8 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r data/lang $lang
  silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
  # Use our special topology... note that later on may have to tune this topology.
  steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

if [ $stage -le 9 ]; then
  # Build a tree using our new topology. This is the critically different
  # step compared with other recipes.
  steps/nnet3/chain/build_tree.sh --cmd "$train_cmd" \
    --context-opts "--context-width=2 --central-position=1" \
    --frame-subsampling-factor 3 \
    5000 data/$train_set $lang $ali_dir $tree_dir
fi

if [ $stage -le 10 ]; then
  echo "$0: creating neural net configs using the xconfig parser";
  num_targets=$(tree-info ${tree_dir}/tree | grep num-pdfs | awk '{print $2}')
  learning_rate_factor=$(echo "print 0.5/$xent_regularize" | python)
  opts="l2-regularize=0.0015 dropout-proportion=0.0 dropout-per-dim=true dropout-per-dim-continuous=true"
  linear_opts="l2-regularize=0.0015 orthonormal-constraint=-1.0"
  output_opts="l2-regularize=0.001"

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-2,-1,0,1,2) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-dropout-layer name=tdnn1 $opts dim=1280
  linear-component name=tdnn2l dim=256 $linear_opts input=Append(-1,0)
  relu-batchnorm-dropout-layer name=tdnn2 $opts input=Append(0,1) dim=1280
  linear-component name=tdnn3l dim=256 $linear_opts
  relu-batchnorm-dropout-layer name=tdnn3 $opts dim=1280
  linear-component name=tdnn4l dim=256 $linear_opts input=Append(-1,0)
  relu-batchnorm-dropout-layer name=tdnn4 $opts input=Append(0,1) dim=1280
  linear-component name=tdnn5l dim=256 $linear_opts
  relu-batchnorm-dropout-layer name=tdnn5 $opts dim=1280 input=Append(tdnn5l, tdnn3l)
  linear-component name=tdnn6l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-dropout-layer name=tdnn6 $opts input=Append(0,3) dim=1280
  linear-component name=tdnn7l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-dropout-layer name=tdnn7 $opts input=Append(0,3,tdnn6l,tdnn4l,tdnn2l) dim=1280
  linear-component name=tdnn8l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-dropout-layer name=tdnn8 $opts input=Append(0,3) dim=1280
  linear-component name=tdnn9l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-dropout-layer name=tdnn9 $opts input=Append(0,3,tdnn8l,tdnn6l,tdnn4l) dim=1280
  linear-component name=tdnn10l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-dropout-layer name=tdnn10 $opts input=Append(0,3) dim=1280
  linear-component name=tdnn11l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-dropout-layer name=tdnn11 $opts input=Append(0,3,tdnn10l,tdnn8l,tdnn6l) dim=1280
  
  linear-component name=prefinal-l dim=256 $linear_opts

  relu-batchnorm-dropout-layer name=prefinal-chain input=prefinal-l $opts dim=1280
  output-layer name=output include-log-softmax=false dim=$num_targets $output_opts bottleneck-dim=256

  relu-batchnorm-dropout-layer name=prefinal-xent input=prefinal-l $opts dim=1280
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor $output_opts bottleneck-dim=256

EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

if [ $stage -le 11 ]; then
  steps/nnet3/chain/train.py --stage $train_stage \
    --use-gpu "wait" \
    --cmd "$decode_cmd" \
    --feat.cmvn-opts "$cmvn_opts" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient $leaky_hmm_coefficient \
    --chain.l2-regularize $l2_regularize \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --egs.dir "$common_egs_dir" \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0" \
    --egs.chunk-width $frames_per_eg \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.num-chunk-per-minibatch $num_chunk_per_minibatch \
    --trainer.frames-per-iter $frames_per_iter \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial $num_jobs_initial \
    --trainer.optimization.num-jobs-final $num_jobs_final \
    --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
    --trainer.optimization.final-effective-lrate $final_effective_lrate \
    --trainer.max-param-change $max_param_change \
    --cleanup.remove-egs $remove_egs \
    --feat-dir data/mfcc_hires_${train_set} \
    --tree-dir $tree_dir \
    --lat-dir $lat_dir \
    --dir $dir || exit 1;
fi

if [ $stage -le 12 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_test $dir $dir/graph || exit 1;
fi

if [ $stage -le 13 ]; then
  for x in $test_sets; do
    nj=$(wc -l data/mfcc_hires_${x}/spk2utt | awk '{print $1}')
    steps/nnet3/decode.sh --cmd "$decode_cmd" --nj $nj \
      --acwt 1.0 --post-decode-acwt 10.0 \
      $dir/graph data/mfcc_hires_${x} $dir/decode_${x} || exit 1;
  done
fi

echo "local/chain/tuning/run_tdnn_1a.sh succeeded"
exit 0;
