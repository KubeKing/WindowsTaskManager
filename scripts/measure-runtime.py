#!/usr/bin/env python3
"""Read CPU time, RSS and physical footprint for this local app only. No dependencies or network access."""
import argparse
import ctypes
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=float, default=60)
parser.add_argument('--label', default='foreground')
parser.add_argument('--executable', type=Path, help='Exact app executable for before/after comparisons')
args = parser.parse_args()
expected = str((args.executable or (Path(__file__).resolve().parent.parent / 'build/Task Manager.app/Contents/MacOS/TaskManager')).resolve())
processes = subprocess.check_output(['/bin/ps', '-axo', 'pid=,command='], text=True)
pids = [int(line.strip().split(None, 1)[0]) for line in processes.splitlines() if line.strip().split(None, 1)[-1] == expected]
if len(pids) != 1:
    raise SystemExit(f'Expected one running project app; found {len(pids)}.')
pid = pids[0]

class RUsageV0(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in [
        'user_time', 'system_time', 'pkg_idle_wkups', 'interrupt_wkups', 'pageins',
        'wired_size', 'resident_size', 'phys_footprint', 'proc_start_abstime', 'proc_exit_abstime']]

libproc = ctypes.CDLL('/usr/lib/libproc.dylib')
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
libproc.proc_pid_rusage.restype = ctypes.c_int

def footprint():
    usage = RUsageV0()
    return usage.phys_footprint / (1024 * 1024) if libproc.proc_pid_rusage(pid, 0, ctypes.byref(usage)) == 0 else None

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
start_footprint = footprint()
start = time.monotonic()
time.sleep(max(1, args.seconds))
end_cpu, end_rss = sample()
elapsed = time.monotonic() - start
end_footprint = footprint()
print(json.dumps({'label': args.label, 'pid': pid, 'elapsed_seconds': round(elapsed, 2), 'cpu_seconds': round(end_cpu-start_cpu, 3), 'percent_one_core': round((end_cpu-start_cpu)/elapsed*100, 2), 'rss_start_mib': round(start_rss, 1), 'rss_end_mib': round(end_rss, 1), 'footprint_start_mib': round(start_footprint, 1) if start_footprint is not None else None, 'footprint_end_mib': round(end_footprint, 1) if end_footprint is not None else None}, indent=2))
