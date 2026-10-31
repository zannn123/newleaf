#!/usr/bin/env python3
"""Where Claude Code's tokens go, read from its own session logs.

Every assistant entry in a log (.jsonl) carries the API's usage block: fresh
input, cache write, cache read and output tokens. A streamed reply can be
logged more than once under the same requestId, so each call counts once.
Totals only; prompt text is never printed.

  measure.py                               last 14 days, every project
  measure.py --days 7 --project Financing  projects whose folder name matches
  measure.py --session FILE.jsonl          one session, request by request
  measure.py --session FILE.jsonl --since 2026-10-31T10:00:00Z --json
"""
import argparse
import collections
import datetime
import glob
import json
import os
import statistics

KEYS = ('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')
ROOT = os.path.join(os.path.expanduser('~'), '.claude', 'projects')


def fmt(n):
    return f'{n / 1e6:,.1f}M' if n >= 1e6 else f'{n / 1e3:,.0f}k'


def when(ts):
    try:
        t = datetime.datetime.fromisoformat(str(ts).replace('Z', '+00:00'))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=datetime.timezone.utc)


def is_prompt(o):
    """A message the person typed: not a tool result, injected meta text or a compaction summary."""
    if o.get('type') != 'user' or o.get('isMeta') or o.get('isSidechain') or o.get('isCompactSummary'):
        return False
    c = (o.get('message') or {}).get('content')
    return isinstance(c, str) or (isinstance(c, list) and bool(c) and not any(
        isinstance(b, dict) and b.get('type') == 'tool_result' for b in c))


def call(o):
    """(requestId, fresh, cache write, cache read, output) of an assistant entry that reached the API,
    else None: <synthetic> entries (written for errors) carry no tokens, and a real call always sends input."""
    m = o.get('message') or {}
    u = m.get('usage')
    if o.get('type') != 'assistant' or not isinstance(u, dict) or m.get('model') == '<synthetic>':
        return None
    sizes = tuple(u.get(k) or 0 for k in KEYS)
    if not any(sizes):
        return None
    return (o.get('requestId') or m.get('id'),) + sizes + (u.get('output_tokens') or 0,)


def read(path, since, prompts=False):
    """(time, entry) for the assistant calls of one log from `since` on, and typed prompts when asked."""
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            if '"usage"' not in line and not (prompts and '"type":"user"' in line and '"tool_result"' not in line):
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            t = when(o.get('timestamp'))
            if t is not None and (since is None or t >= since):
                yield t, o


def session(path, since=None):
    """Totals for one session, its subagents included, from `since` on."""
    seen, ctx, turns = set(), [], []
    tot = dict(prompts=0, calls=0, fresh=0, cache_write=0, cache_read=0, output=0)
    sub = dict(calls=0, fresh=0, cache_write=0, cache_read=0, output=0)

    def add(bucket, c):
        bucket['calls'] += 1
        for k, v in zip(('fresh', 'cache_write', 'cache_read', 'output'), c[1:]):
            bucket[k] += v

    for _, o in read(path, since, prompts=True):
        if is_prompt(o):
            tot['prompts'] += 1
            turns.append(dict(calls=0, input=0, output=0, start=0))
            continue
        c = call(o)
        if c is None or o.get('isSidechain') or c[0] in seen:
            continue
        seen.add(c[0])
        add(tot, c)
        size = sum(c[1:4])
        ctx.append(size)
        if not turns:
            turns.append(dict(calls=0, input=0, output=0, start=0))
        t = turns[-1]
        t['start'] = t['start'] or size
        t['calls'] += 1
        t['input'] += size
        t['output'] += c[4]
    for p in glob.glob(os.path.join(os.path.splitext(path)[0], 'subagents', '*.jsonl')):
        for _, o in read(p, since):
            c = call(o)
            if c is not None and c[0] not in seen:
                seen.add(c[0])
                add(sub, c)
    inp = tot['fresh'] + tot['cache_write'] + tot['cache_read']
    sub_total = sub['fresh'] + sub['cache_write'] + sub['cache_read'] + sub['output']
    return dict(tot, input=inp, sub=sub, total=inp + tot['output'] + sub_total,
                ctx_first=ctx[0] if ctx else 0, ctx_last=ctx[-1] if ctx else 0,
                ctx_median=int(statistics.median(ctx)) if ctx else 0, ctx_max=max(ctx, default=0),
                turns=[t for t in turns if t['calls']])


def print_session(r):
    print(f'{r["prompts"]} typed prompts, {r["calls"]} API calls (+{r["sub"]["calls"]} in subagents)')
    print(f'input {fmt(r["input"])} = fresh {fmt(r["fresh"])} + cache write {fmt(r["cache_write"])} + '
          f'cache read {fmt(r["cache_read"])};  output {fmt(r["output"])};  all tokens {fmt(r["total"])}')
    print(f'context per call: first {fmt(r["ctx_first"])}, median {fmt(r["ctx_median"])}, max {fmt(r["ctx_max"])}')
    for i, t in enumerate(r['turns'], 1):
        print(f'  request {i:3}: {t["calls"]:3} calls, input {fmt(t["input"]):>7}, starts at {fmt(t["start"]):>6}')


def summary(root, days, project):
    since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
    calls = {}
    for path in glob.glob(os.path.join(root, '**', '*.jsonl'), recursive=True):
        proj = os.path.relpath(path, root).split(os.sep)[0]
        if project and project.lower() not in proj.lower():
            continue
        sub = os.sep + 'subagents' + os.sep in path
        for t, o in read(path, since):
            c = call(o)
            if c is not None:
                calls[c[0] or f'{path}:{t}'] = dict(
                    t=t, proj=proj, session=o.get('sessionId'), sub=sub or bool(o.get('isSidechain')),
                    model=(o.get('message') or {}).get('model', '?'), fresh=c[1], cw=c[2], cr=c[3], out=c[4])
    rs = list(calls.values())
    if not rs:
        print(f'no API calls in the last {days} days under {root}')
        return

    def ctx(xs):
        return sum(x['fresh'] + x['cw'] + x['cr'] for x in xs)

    def tot(xs, k):
        return sum(x[k] for x in xs)

    all_in, out = ctx(rs), tot(rs, 'out')
    print(f'last {days} days: {len(rs)} API calls')
    print(f'input {fmt(all_in)} = fresh {fmt(tot(rs, "fresh"))} + cache write {fmt(tot(rs, "cw"))} + '
          f'cache read {fmt(tot(rs, "cr"))};  output {fmt(out)} ({out / (all_in + out):.1%} of all tokens)')
    groups = collections.defaultdict(list)
    for x in rs:
        groups[x['proj']].append(x)
    print('\nby project:')
    for p, xs in sorted(groups.items(), key=lambda kv: -ctx(kv[1])):
        print(f'  {p[:55]:55} calls {len(xs):6}  input {fmt(ctx(xs)):>8}  output {fmt(tot(xs, "out")):>7}')
    print('\nmain thread vs subagents:')
    for name, xs in (('main', [x for x in rs if not x['sub']]), ('subagents', [x for x in rs if x['sub']])):
        print(f'  {name:10} calls {len(xs):6}  input {fmt(ctx(xs)):>8} ({ctx(xs) / all_in:.0%})')
    print('\nby model:')
    for mdl in sorted({x['model'] for x in rs}):
        xs = [x for x in rs if x['model'] == mdl]
        print(f'  {mdl:30} calls {len(xs):6}  input {fmt(ctx(xs)):>8}  output {fmt(tot(xs, "out"))}')
    sizes = sorted(x['fresh'] + x['cw'] + x['cr'] for x in rs if not x['sub'])
    if sizes:
        q = lambda p: sizes[min(len(sizes) - 1, int(p * len(sizes)))]  # noqa: E731
        print(f'\ncontext re-sent per call (main thread): median {fmt(q(.5))}, p75 {fmt(q(.75))}, '
              f'p90 {fmt(q(.9))}, max {fmt(sizes[-1])}')
    first = {}
    for x in sorted(rs, key=lambda x: x['t']):
        if not x['sub']:
            first.setdefault(x['session'], x)
    fl = sorted(x['fresh'] + x['cw'] + x['cr'] for x in first.values())
    if fl:
        print(f'first call of a session: median {fmt(fl[len(fl) // 2])}, min {fmt(fl[0])}, max {fmt(fl[-1])} '
              f'over {len(fl)} sessions')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=ROOT, help='Claude Code projects folder (default: %(default)s)')
    ap.add_argument('--days', type=int, default=14)
    ap.add_argument('--project', default='', help='only project folders whose name contains this')
    ap.add_argument('--session', help='one session log (.jsonl)')
    ap.add_argument('--since', help='with --session: only entries at or after this time (ISO 8601)')
    ap.add_argument('--json', action='store_true', help='with --session: print the totals as JSON')
    a = ap.parse_args()
    if not a.session:
        summary(a.root, a.days, a.project)
        return
    since = when(a.since) if a.since else None
    if a.since and since is None:
        ap.error(f'--since is not an ISO 8601 time: {a.since}')
    r = session(a.session, since)
    if a.json:
        print(json.dumps(r))
    else:
        print_session(r)


if __name__ == '__main__':
    main()
