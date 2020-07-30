#!/usr/bin/env python3
import sys, argparse, codecs, os
import random

KALDI_ROOT='/home/speechio/work/kaldi'
ADD_NOISE_TOOL=os.path.join(KALDI_ROOT, 'src', 'featbin', 'wav-reverberate')

parser = argparse.ArgumentParser()

parser.add_argument("noise_list", type=str, default="", help="")
parser.add_argument("snr_lower", type=int, default=0, help="")
parser.add_argument("snr_upper", type=int, default=20, help="")
parser.add_argument("odir", type=str, default="", help="")

parser.add_argument("--list", type=str, default="", help="wav.list")
parser.add_argument("--scp", type=str, default="", help="wav.scp")
parser.add_argument("--corpus", type=str, default="", help="corpus dir")

parser.add_argument("--normalize_output", type=str, default="false", help="true / false")
parser.add_argument("--background_mode", type=str, default="true", help="true / false")
parser.add_argument("--random_noise_position", type=str, default="true", help="true / false")
parser.add_argument("--key_append_snr", type=str, default="true", help="true / false")
parser.add_argument("--key_append_string", type=str, default="", help="any aux string")

args = parser.parse_args()

assert(args.list != "" or args.scp != "" or args.corpus != "")

# setup opts
opts=""
assert(args.normalize_output == "true" or args.normalize_output == "false")
opts += ' --normalize-output={} '.format(args.normalize_output)

assert(args.background_mode == "true" or args.background_mode == "false")
opts += ' --background-mode={} '.format(args.background_mode)

assert(args.random_noise_position == "true" or args.random_noise_position == "false")
opts += ' --random-noise-position={} '.format(args.random_noise_position)

assert(args.key_append_snr == "true" or args.key_append_snr == "false")

# load noise
noise_list = []
with open(args.noise_list, 'r') as f:
  for l in f:
    if l.strip() != "":
      noise_list.append(l.strip())

sys.stderr.write("Noise Library Size:{}\n".format(len(noise_list)))

snr_list = list(range(args.snr_lower, args.snr_upper))

keys = []
wavs = []

# load input wavs
if args.list != "":
  with open(args.list, 'r') as file_list:
    for l in file_list:
      f = l.strip()
      if f != "":
        filename = os.path.basename(f)
        key, ext = os.path.splitext(filename)
        assert(len(keys) == len(wavs))
        keys.append(key)
        wavs.append(f)

elif args.scp != "":
  with open(args.scp, 'r') as scp_list:
    for l in scp_list:
      if l.strip() != "":
        key, f = l.split(maxsplit=1)
        assert(len(keys) == len(wavs))
        keys.append(key)
        wavs.append(f.strip())

elif args.corpus != "":
  pass

else:
  sys.stderr.write("not list/scp/corpus ?")

assert(len(keys) == len(wavs))

# add noise
for i in range(len(keys)):
  key = keys[i]
  wav = wavs[i]

  noise = random.choice(noise_list)
  snr = random.choice(snr_list)

  new_key = key
  if (args.key_append_snr):
    new_key += '__SNR{}dB'.format(snr)
  if (args.key_append_string != ''):
    new_key += '__{}'.format(args.key_append_string)
  
  cmd = ADD_NOISE_TOOL + opts + \
    ' additive-signal={} '.format(noise) + \
    ' --snr={} '.format(snr) + \
    ' --start-time={} '.format(0) + \
    wav + ' ' + os.path.join(args.odir, new_key+'.wav')
  print(i, cmd)
  #os.system()