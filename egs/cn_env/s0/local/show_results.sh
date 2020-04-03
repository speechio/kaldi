# !/bin/bash
echo "-------------------- Show Results --------------------"
  # gmm models
  for m in exp/*/decode_*test*; 
    do [ -d $m ] && grep WER $m/cer_* | utils/best_wer.sh; 
  done 2>/dev/null

  # chain models
  for m in exp/*/*/decode_*test*;
    do [ -d $m ] && grep WER $m/cer_* | utils/best_wer.sh; 
  done 2>/dev/null
echo "------------------------------------------------------"
