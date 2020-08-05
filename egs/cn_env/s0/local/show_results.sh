# !/bin/bash
echo "-------------------- Show Results --------------------"
  # gmm models
for x in dev test; do
  for m in exp/*/decode_*$x*; 
    do [ -d $m ] && grep WER $m/cer_* | utils/best_wer.sh; 
  done 2>/dev/null

  # chain models
  for m in exp/*/*/decode_*$x*;
    do [ -d $m ] && grep WER $m/cer_* | utils/best_wer.sh; 
  done 2>/dev/null

  echo -e "\n"
done
echo "------------------------------------------------------"
