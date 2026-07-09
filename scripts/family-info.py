#!/usr/bin/env python3
import json, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(ROOT, 'variants.json')) as f:
    data = json.load(f)

family = sys.argv[1]
info = data['families'].get(family)
if not info:
    print(f"Unknown family: {family}", file=sys.stderr)
    sys.exit(1)

key = sys.argv[2] if len(sys.argv) > 2 else 'all'
if key == 'all':
    print(json.dumps(info))
else:
    print(info.get(key, ''))
