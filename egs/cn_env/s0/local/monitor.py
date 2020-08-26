#!/usr/bin/env python3
import sys, glob, os

if len(sys.argv) != 3:
  sys.stderr.write("board.py exp_dir train.log")
  exit(-1)

exp_dir = sys.argv[1]
train_log = sys.argv[2]

MAX_NUM_JOBS = 16

class IterInfo:
  def __init__(self):
    self.index = 0
    self.lr = 0.0
    self.njobs = 0
    self.train_subset_loss = 0.0
    self.valid_subset_loss = 0.0
    self.parallel_job_loss = []

iters = []

assert(os.path.isfile(train_log))
with open(train_log, 'r') as f:
  for l in f:
    if 'Iter' in l:
      it = IterInfo()
      cols = l.split()
      it.index = int(cols[9].split('/')[0])
      it.lr = float(cols[-1])
      assert(it.index == len(iters))
      iters.append(it)

for it in iters:
  # collect train subset loss
  log = os.path.join(exp_dir, 'log', 'compute_prob_train.{}.log'.format(it.index))
  if (os.path.isfile(log)):
    with open(log, 'r') as f:
      for l in f:
        if "'output'" in l:
          cols = l.split()
          it.train_subset_loss = float(cols[7])

  # collect valid subset loss
  log = os.path.join(exp_dir, 'log', 'compute_prob_valid.{}.log'.format(it.index))
  if (os.path.isfile(log)):
    with open(log, 'r') as f:
      for l in f:
        if "'output'" in l:
          cols = l.split()
          it.valid_subset_loss = float(cols[7])
  
  # collect parallel models' loss
  jobs_log_list = glob.glob(os.path.join(exp_dir, 'log', 'train.{}.*.log'.format(it.index)))
  it.njobs = len(jobs_log_list)

  for i in range(1, it.njobs+1):
    log = os.path.join(exp_dir, 'log', 'train.{}.{}.log'.format(it.index, i))
    assert(os.path.isfile(log))
    with open(log, 'r') as f:
      for l in f:
        if "Overall average objective function for 'output'" in l:
          tmp = l.split('over')
          tmp2 = tmp[0].split()
          it.parallel_job_loss.append(float(tmp2[-1]))


sys.stdout.write('iter, njobs, lr, train_subset_loss, valid_subset_loss')
for i in range(1, MAX_NUM_JOBS + 1):
  sys.stdout.write(', job{}_loss'.format(i))
sys.stdout.write('\n')

for it in iters:
  sys.stdout.write('{:5d}, {:3d}, {:10.7f}, {:10.4f}, {:10.4f}'.format(it.index, it.njobs, it.lr, it.train_subset_loss, it.valid_subset_loss))
  for job_loss in it.parallel_job_loss:
    sys.stdout.write(', {}'.format(job_loss))
  sys.stdout.write('\n')
