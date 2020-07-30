#!/bin/bash
set -e

# as 1a, add specaug, and minor modification to hyper-params

# ---------- CONFIG ---------- #
nj=20
stage=0
train_stage=-10
get_egs_stage=-10
dir=exp/chain/cnn_tdnnf_1b
affix=
tree_affix=
decode_iter=

train_set="train"
test_sets="test"

srand=0
remove_egs=true
reporting_email=

# training options
num_epochs=4
initial_effective_lrate=0.00015
final_effective_lrate=0.000015
max_param_change=2.0
num_jobs_initial=3
num_jobs_final=16
num_chunk_per_minibatch=128,64  # minibatch_size
frames_per_iter=3000000
chunk_width=150,110,100
leaky_hmm_coefficient=0.1
l2_regularize=0.0
remove_egs=true
common_egs_dir=
xent_regularize=0.1
dropout_schedule='0,0@0.20,0.5@0.50,0'

# ---------- END OF CONFIG ---------- #

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

  num_targets=$(tree-info $tree_dir/tree | grep num-pdfs | awk '{print $2}')
  learning_rate_factor=$(echo "print (0.5/$xent_regularize)" | python)
  cnn_opts="l2-regularize=0.01"
  affine_opts="l2-regularize=0.008 dropout-proportion=0.0 dropout-per-dim=true dropout-per-dim-continuous=true"
  tdnnf_first_opts="l2-regularize=0.008 dropout-proportion=0.0 bypass-scale=0.0"
  tdnnf_opts="l2-regularize=0.008 dropout-proportion=0.0 bypass-scale=0.75"
  linear_opts="l2-regularize=0.008 orthonormal-constraint=-1.0"
  prefinal_opts="l2-regularize=0.008"
  output_opts="l2-regularize=0.005"

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig

  input dim=40 name=input

  # MFCC to filterbank
  idct-layer name=idct input=input dim=40 cepstral-lifter=22 affine-transform-file=$dir/configs/idct.mat
  batchnorm-component name=idct-batchnorm input=idct

  # spec augmentation
  spec-augment-layer name=idct-spec-augment freq-max-proportion=0.5 time-zeroed-proportion=0.2 time-mask-max-frames=20

  # CNN layers
  conv-relu-batchnorm-layer name=cnn1 $cnn_opts height-in=40 height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=64 learning-rate-factor=0.333 max-change=0.25
  conv-relu-batchnorm-layer name=cnn2 $cnn_opts height-in=40 height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=64
  conv-relu-batchnorm-layer name=cnn3 $cnn_opts height-in=40 height-out=20 height-subsample-out=2 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=128
  conv-relu-batchnorm-layer name=cnn4 $cnn_opts height-in=20 height-out=20 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=128
  conv-relu-batchnorm-layer name=cnn5 $cnn_opts height-in=20 height-out=10 height-subsample-out=2 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=256
  conv-relu-batchnorm-layer name=cnn6 $cnn_opts height-in=10 height-out=10 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=256

  # the first TDNN-F layer has no bypass (since dims don't match), and a larger bottleneck so the
  # information bottleneck doesn't become a problem.
  tdnnf-layer name=tdnnf7 $tdnnf_first_opts dim=1536 bottleneck-dim=256 time-stride=0
  tdnnf-layer name=tdnnf8 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf9 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf10 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf11 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf12 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf13 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf14 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf15 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf16 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf17 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf18 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3

  linear-component name=prefinal-l dim=256 $linear_opts

  # adding the layers for chain branch
  prefinal-layer name=prefinal-chain input=prefinal-l $prefinal_opts big-dim=1536 small-dim=256
  output-layer name=output include-log-softmax=false dim=$num_targets $output_opts

  # adding the layers for xent branch
  prefinal-layer name=prefinal-xent input=prefinal-l $prefinal_opts big-dim=1536 small-dim=256
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor $output_opts

EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

if [ $stage -le 11 ]; then
  steps/nnet3/chain/train.py --stage $train_stage \
    --use-gpu "wait" \
    --cmd "$decode_cmd" \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient $leaky_hmm_coefficient \
    --chain.l2-regularize $l2_regularize \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.add-option="--optimization.memory-compression-level=2" \
    --trainer.srand=$srand \
    --trainer.max-param-change $max_param_change \
    --trainer.num-epochs $num_epochs \
    --trainer.frames-per-iter $frames_per_iter \
    --trainer.num-chunk-per-minibatch $num_chunk_per_minibatch \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.optimization.num-jobs-initial $num_jobs_initial \
    --trainer.optimization.num-jobs-final $num_jobs_final \
    --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
    --trainer.optimization.final-effective-lrate $final_effective_lrate \
    --egs.chunk-width $chunk_width \
    --egs.dir "$common_egs_dir" \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0 --constrained false" \
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

echo "local/chain/tuning/cnn_tdnnf_1a.sh succeeded"
exit 0;
