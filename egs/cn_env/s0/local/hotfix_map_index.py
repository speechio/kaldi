#/usr/bin/env python3

import os, sys, codecs, argparse

ifile=sys.argv[1]
vocab_file=sys.argv[2]
ofile=sys.argv[3]

fo = open(ofile, 'w+')

vocab={}
with codecs.open(vocab_file, 'r', 'utf8') as f:
  for l in f:
    if l.strip() != "":
      word, word_id = l.split()
      vocab[word] = word_id

print(len(vocab))
unk_id = vocab['<unk>']

print('unk_id: ' + unk_id)

with codecs.open(ifile, 'r', 'utf8') as f:
  for l in f:
    if l.strip() != "":
      fields = l.split()
      weight = fields[0]
      tokens = fields[1:]

      line = weight
      for token in tokens:
        token_id = vocab.get(token, unk_id)
        if (token_id == unk_id):
            print("warning: found unk word " + token)
        line = line + ' ' + token_id
      
      fo.write(line + '\n')

fo.close()
