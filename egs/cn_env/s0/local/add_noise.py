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
parser.add_argument("--trans", type=str, default="", help="trans.txt")
parser.add_argument("--utt2spk", type=str, default="", help="utt2spk")

parser.add_argument("--normalize_output", type=str, default="false", help="true / false")
parser.add_argument("--background_mode", type=str, default="true", help="true / false")
parser.add_argument("--random_noise_position", type=str, default="true", help="true / false")
parser.add_argument("--key_append_snr", type=str, default="true", help="true / false")
parser.add_argument("--key_append_string", type=str, default="", help="any aux string")

args = parser.parse_args()

assert(
  (args.list != '') or
  (args.scp != '')
)

# setup opts
opts=' --start-time={} '.format(0) # add noise from beginning of audio

assert(args.normalize_output == "true" or args.normalize_output == "false")
opts += ' --normalize-output={} '.format(args.normalize_output)

assert(args.background_mode == "true" or args.background_mode == "false")
opts += ' --background-mode={} '.format(args.background_mode)

assert(args.random_noise_position == "true" or args.random_noise_position == "false")
opts += ' --random-noise-position={} '.format(args.random_noise_position)

assert(args.key_append_snr == "true" or args.key_append_snr == "false")

# load noise library
noise_list = []
with open(args.noise_list, 'r') as f:
  for l in f:
    l = l.strip()
    if l != "":
      noise_list.append(l)
sys.stderr.write("Loaded Noise Library # wavs:{}\n".format(len(noise_list)))

snr_list = list(range(args.snr_lower, args.snr_upper))
sys.stderr.write("Add noise SNR range:[{},{}]dB\n".format(snr_list[0], snr_list[-1]))

keys = []
wavs = {}

if args.list != '':
  sys.stderr.write('Adding noise to wav list...\n')
  # load list
  assert(os.path.isfile(args.list))
  with open(args.list, 'r') as wav_list:
    for l in wav_list:
      f = l.strip()
      if f != "":
        filename = os.path.basename(f)
        key, ext = os.path.splitext(filename)
        keys.append(key)
        assert(wavs.get(key) == None) # check duplicated key
        wavs[key] = f
  sys.stderr.write('# of wavs:{}\n'.format(len(wavs)))

  # add noise
  for i in range(len(keys)):
    key = keys[i]
    wav = wavs.get(key)
    assert(wav != None) # no wav match the key

    noise = random.choice(noise_list)
    snr = random.choice(snr_list)

    new_key = key
    if (args.key_append_snr):
      new_key += '__SNR{}dB'.format(snr)
    if (args.key_append_string != ''):
      new_key += '__{}'.format(args.key_append_string)
    
    new_wav = os.path.join(args.odir, new_key+'.wav')

    sys.stderr.write('{}  key={}  f={}  noise={}  snr={}dB  new_key={}  new_f={}\n'.format(i, key, wav, noise, snr, new_key, new_wav))
    cmd = ADD_NOISE_TOOL + opts + ' additive-signal={} '.format(noise) + ' --snr={} '.format(snr) + wav + ' ' + new_wav
    #os.system(cmd)

elif args.scp != "":
  sys.stderr.write('Adding noise to wav scp...\n')
  # load scp
  assert(os.path.isfile(args.scp))
  with open(args.scp, 'r') as scp_list:
    for l in scp_list:
      l = l.strip()
      if (l != ''):
        key, f = l.split(maxsplit=1)
        assert(len(keys) == len(wavs))
        keys.append(key)
        assert(wavs.get(key) == None) # check duplicated key
        wavs[key] = f
  sys.stderr.write('# of wavs loaded:{}\n'.format(len(wavs)))

  # load trans
  trans = {}
  if args.trans != '':
    assert(os.path.isfile(args.trans))
    with codecs.open(args.trans, 'r', 'utf8') as trans_list:
      for l in trans_list:
        l = l.strip()
        if (l != ''):
          key, text = l.split(maxsplit=1)
          assert(trans.get(key) == None)
          trans[key] = text
  sys.stderr.write('# of trans loaded:{}\n'.format(len(trans)))

  # load utt2spk
  utt2spk = {}
  if args.utt2spk != '':
    assert(os.path.isfile(args.utt2spk))
    with open(args.utt2spk, 'r') as utt2spk_file:
      for l in utt2spk_file:
        l = l.strip()
        if (l != ''):
          key, spk = l.split(maxsplit=1)
          assert(utt2spk.get(key) == None)
          utt2spk[key] = spk
  sys.stderr.write('# of utt2spk loaded:{}\n'.format(len(utt2spk)))

  # add noise
  os.mkdir(args.odir)
  os.mkdir(os.path.join(args.odir, 'wav'))

  oscp = open(os.path.join(args.odir, 'wav.scp'), 'w+')
  if args.trans != '':
    otrans = codecs.open(os.path.join(args.odir, 'trans.txt'), 'w+', 'utf8')
  outt2spk = open(os.path.join(args.odir, 'utt2spk'), 'w+')

  for i in range(len(keys)):
    key = keys[i]
    wav = wavs.get(key)
    assert(wav != None) # no wav match the key?

    noise = random.choice(noise_list)
    snr = random.choice(snr_list)

    new_key = key
    if (args.key_append_snr):
      new_key += '__SNR{}dB'.format(snr)
    if (args.key_append_string != ''):
      new_key += '__{}'.format(args.key_append_string)

    new_wav = os.path.join(args.odir, 'wav', new_key+'.wav')

    sys.stderr.write('{}  key={}  f={}  noise={}  snr={}dB  new_key={}  new_f={}\n'.format(i, key, wav, noise, snr, new_key, new_wav))
    cmd = ADD_NOISE_TOOL + opts + ' additive-signal={} '.format(noise) + ' --snr={} '.format(snr) + wav + ' ' + new_wav
    #os.system(cmd)

    # write new wav.scp
    oscp.write('{}\t{}\n'.format(new_key, os.path.join('wav', new_key+'.wav')))
    
    # write new trans.txt
    if (args.trans != ''):
      text = trans.get(key)
      assert(text != None) # missing trans?
      otrans.write('{}\t{}\n'.format(new_key, text))
    
    # write new utt2spk
    spk = utt2spk.get(key)
    if spk != None:
      outt2spk.write('{}\t{}\n'.format(new_key, spk))
    else:
      outt2spk.write('{}\t{}\n'.format(new_key, key))
  
  oscp.close()
  if (args.trans != ''):
    otrans.close()
  outt2spk.close()

else:
  sys.stderr.write("not list/scp?")
