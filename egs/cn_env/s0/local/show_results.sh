# !/bin/bash
test_sets="dev test"
for s in $test_sets; do
  echo "----- $s -----:"

  # gmm models
  for m in exp/*/decode_${s}; 
    do [ -d $m ] && grep WER $m/cer_* | utils/best_wer.sh; 
  done 2>/dev/null

  # chain models
  for m in exp/*/*/decode_${s};
    do [ -d $m ] && grep WER $m/cer_* | utils/best_wer.sh; 
  done 2>/dev/null

  echo ""
done 2>/dev/null
