#!/usr/bin/env python3
"""Append one round to a world's log.jsonl and refresh its log.js mirror.

    python3 shared/logrow.py gitanjali-60 3 row.json

row.json holds the round's fields (title/changed/why/critic/score/gap/noticed and
optionally stop/stop_reason). round number, timestamp, the six shot paths and the
version snapshot path are filled in here so they can never drift from the layout.
"""
import json, subprocess, sys, os, pathlib

world, rnd, src = sys.argv[1], int(sys.argv[2]), sys.argv[3]
row = json.load(open(src, encoding='utf-8'))
shots = sorted((pathlib.Path(world) / 'shots' / str(rnd)).glob('*.png'))
out = {'round': rnd,
       'at': subprocess.check_output(['date', '-u', '+%Y-%m-%dT%H:%MZ']).decode().strip()}
out.update(row)
out['shots'] = ['shots/%d/%s' % (rnd, p.name) for p in shots]
out['version'] = 'versions/%d/index.html' % rnd
with open(os.path.join(world, 'log.jsonl'), 'a', encoding='utf-8') as f:
    f.write(json.dumps(out, ensure_ascii=False) + '\n')
subprocess.check_call(['sh', 'shared/mklog.sh', world])
print('round %d appended (%d shots)' % (rnd, len(shots)))
