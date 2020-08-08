#!/usr/bin/env python3
import sys, os, argparse
import subprocess, multiprocessing

parser = argparse.ArgumentParser()
parser.add_argument("cmd_list", type=str, help="cmd.list")
parser.add_argument("--nj", type=int, default=20, help="")
args = parser.parse_args()

def run(cmd):
  #sys.stderr.write(cmd + '\n')
  #subprocess.run(cmd.split())
  os.system(cmd)

tasks = []
with open(args.cmd_list, 'r') as f:
  for l in f:
    cmd = l.strip()
    if cmd != '':
      tasks.append(cmd)

sys.stderr.write("number of tasks N={}, number of workers M={}.\n".format(len(tasks), args.nj))

pool = multiprocessing.Pool(args.nj)
results = [ pool.apply_async(run, (task,)) for task in tasks ]
output = [ res.get() for res in results ]
