#!/usr/bin/env python3
"""Offline CI validation without shell interpolation of repository filenames."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate(mode):
    if mode == 'json':
        paths = [p for p in ROOT.rglob('*.json') if '.git' not in p.parts]
    elif mode == 'evals':
        paths = list(ROOT.glob('synapse-*/evals/evals.json'))
    else:
        paths = list(ROOT.glob('synapse-*/SKILL.md'))
    if not paths:
        raise ValueError('No fixtures found for ' + mode)
    for path in sorted(paths):
        text = path.read_text(encoding='utf-8')
        if mode == 'frontmatter':
            match = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
            if not match or any(not re.search(r'^' + key + ':', match[1], re.M)
                                for key in ('name', 'description')):
                raise ValueError('Missing frontmatter fields: ' + str(path))
        else:
            data = json.loads(text)
            if mode == 'evals':
                if not data.get('skill_name') or not data.get('evals'):
                    raise ValueError('Missing skill_name or evals: ' + str(path))
                for item in data['evals']:
                    if any(key not in item for key in ('id', 'prompt', 'assertions')):
                        raise ValueError('Invalid eval: ' + str(path))
        print('OK:', path.relative_to(ROOT))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['json', 'evals', 'frontmatter'])
    validate(parser.parse_args().mode)
