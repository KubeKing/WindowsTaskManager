#!/usr/bin/env python3
"""Read CPU time/RSS for this local app only. No dependencies or network access."""
import argparse
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=float, default=60)
parser.add_argument('--label', default='foreground')
args = parser.parse_args()
expected = str(Path(__file__).resolve().parent.parent / 'build/Task Manager.app/Contents/MacOS/TaskManager')
processes = subprocess.check_output(['/bin/ps', '-axo', 'pid=,command='], text=True)
pids = [int(line.strip().split(None, 1)[0]) for line in processes.splitlines() if line.strip().split(None, 1)[-1] == expected]
if len(pids) != 1:
    raise SystemExit(f'Expected one running project app; found {len(pids)}.')
pid = pids[0]

def sample():
    fields = subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'time=', '-o', 'rss='], text=True).split()
    total = 0.0
    clock = fields[0]
    if '-' in clock:
        days, clock = clock.split('-'); total += float(days) * 86400
    for index, value in enumerate(reversed(clock.split(':'))):
        total += float(value) * 60 ** index
    return total, int(fields[1]) / 1024

start_cpu, start_rss = sample()
start = time.monotonic()
time.sleep(max(1, args.seconds))
end_cpu, end_rss = sample()
elapsed = time.monotonic() - start
print(json.dumps({'label': args.label, 'pid': pid, 'elapsed_seconds': round(elapsed, 2), 'cpu_seconds': round(end_cpu-start_cpu, 3), 'percent_one_core': round((end_cpu-start_cpu)/elapsed*100, 2), 'rss_start_mib': round(start_rss, 1), 'rss_end_mib': round(end_rss, 1)}, indent=2))
