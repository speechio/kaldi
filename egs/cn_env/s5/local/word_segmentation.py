#!/usr/bin/env python
# encoding=utf-8
# Copyright 2019 Jiayu DU
# Apache 2.0

import sys, argparse, codecs
import jieba

parser = argparse.ArgumentParser()
parser.add_argument("word_seg_vocab", type=str, help="JIEBA vocabulary for word segmentation.")
parser.add_argument("itext", type=str, help="input text, one sentence per line.")
parser.add_argument("otext", type=str, help="output word-segmented text.")
parser.add_argument("--has_key", action="store_true", help="input text has Kaldi's key as first field.")
parser.add_argument("--log_interval", type=int, default=100000, help="log interval in number of processed lines.")
args = parser.parse_args()

counter = 0

jieba.set_dictionary(args.word_seg_vocab)
fo = codecs.open(args.otext, 'w+', 'utf8')
for line in codecs.open(args.itext, 'r', 'utf8'):
  if args.has_key:
    key,sentence = line.strip().split('\t',1)
  else:
    sentence = line.strip()

  words = jieba.cut(sentence, HMM=False) # turn off HMM-based new word discovery

  if args.has_key:
    fo.write(key + u'\t' + u' '.join(words) + u'\n')
  else:
    fo.write(u' '.join(words) + u'\n')

  counter += 1
  if (counter % args.log_interval) == 0:
    sys.stderr.write(parser.prog + ':{:>15} lines done.\n'.format(counter))

sys.stderr.write(parser.prog + ':{:>15} lines done in total.\n'.format(counter))

fo.close()
