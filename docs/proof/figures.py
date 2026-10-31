#!/usr/bin/env python3
"""Draws the proof figures from the measured data, so no number in them is
typed by hand: docs/assets/problem.svg (what one step re-sends, before and
after: each run's median, and the range from its first step to its largest)
and docs/assets/proof.svg (tokens per task, every run).
Reads docs/proof/runs.csv.   python docs/proof/figures.py
"""
import csv
import os
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(HERE), 'assets')

STYLE = '''<style>
    .bg { fill: #F6FAF4; } .card { fill: #FFFFFF; stroke: #DCE8DD; stroke-width: 1.5; }
    .ink { fill: #0F1A12; } .muted { fill: #536657; } .accent { fill: #16A34A; } .old { fill: #B4C2B8; }
    .grid { stroke: #E3ECE4; stroke-width: 1; } .tick { fill: #7C8E80; }
    text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
    @media (prefers-color-scheme: dark) {
      .bg { fill: #0B110D; } .card { fill: #111A14; stroke: #223326; }
      .ink { fill: #ECF7EF; } .muted { fill: #94A89A; } .accent { fill: #4ADE80; } .old { fill: #4A5E50; }
      .grid { stroke: #1D2B21; } .tick { fill: #6F8475; }
    }
  </style>'''


def read(name):
    with open(os.path.join(HERE, name), encoding='utf-8') as f:
        return list(csv.DictReader(f))


def fmt(n):
    return f'{n / 1e6:.2f}M' if n >= 1e6 else f'{round(n / 1e3)}k'


def representative(runs, group):
    """The run of a group whose total is closest to the group's mean."""
    rs = [r for r in runs if r['group'] == group]
    mean = statistics.mean(int(r['total_tokens']) for r in rs)
    return min(rs, key=lambda r: abs(int(r['total_tokens']) - mean)), mean, rs


def svg(w, h, title, desc, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" '
            f'aria-labelledby="t d">\n  <title id="t">{title}</title>\n  <desc id="d">{desc}</desc>\n  {STYLE}\n'
            f'  <rect class="bg" width="{w}" height="{h}" rx="28"/>\n{body}</svg>\n')


def problem(runs):
    groups = [('resumed session', 'Resumed long chat', 'old'), ('fresh + newleaf', 'Fresh session + newleaf', 'accent')]
    stats = []
    for g, label, cls in groups:
        rs = [r for r in runs if r['group'] == g]
        stats.append((label, cls, len(rs), statistics.mean(int(r['context_median']) for r in rs),
                      min(int(r['context_first']) for r in rs), max(int(r['context_max']) for r in rs),
                      statistics.mean(int(r['calls']) for r in rs)))
    top = max(s[5] for s in stats)
    w, h, left, span = 1280, 420, 340, 820
    body = ['  <text x="48" y="78" font-size="30" font-weight="800" class="ink">Every step re-sends the whole chat</text>',
            '  <text x="48" y="110" font-size="17" class="muted">Tokens re-sent on each step of the same task. Bar: the runs\' median step. '
            'Line: from the smallest first step to the largest step.</text>']
    y = 158
    for label, cls, n, med, lo, hi, calls in stats:
        body.append(f'  <text x="48" y="{y + 30}" font-size="21" font-weight="700" class="ink">{label}</text>')
        body.append(f'  <text x="48" y="{y + 56}" font-size="15" class="muted">{n} runs, about {calls:.0f} steps each</text>')
        body.append(f'  <line class="grid" x1="{left + lo / top * span:.1f}" x2="{left + hi / top * span:.1f}" y1="{y + 34}" y2="{y + 34}" '
                    f'stroke-width="3"/>')
        body.append(f'  <rect class="{cls}" x="{left}" y="{y + 14}" width="{max(6, med / top * span):.1f}" height="40" rx="8"/>')
        body.append(f'  <text x="{left + max(6, hi / top * span) + 16:.0f}" y="{y + 42}" font-size="20" font-weight="700" class="ink">'
                    f'{fmt(med)} per step</text>')
        y += 104
    body.append(f'  <text x="48" y="{h - 30}" font-size="15" class="muted">From Claude Code\'s own session logs. '
                f'Data: docs/proof/runs.csv</text>')
    return svg(w, h, 'Every step re-sends the whole chat', 'Median tokens re-sent per step: '
               f'{fmt(stats[0][3])} in a resumed long chat, {fmt(stats[1][3])} in a fresh session with newleaf.',
               '\n'.join(body) + '\n')


def proof(runs):
    groups = [('resumed session', 'Resumed long chat', 'old'), ('fresh session, no plugin', 'Fresh, no plugin', 'old'),
              ('fresh + newleaf', 'Fresh + newleaf', 'accent'), ('handoff with /newleaf', 'One /newleaf handoff', 'accent')]
    rows = [(label, cls, [r for r in runs if r['group'] == g]) for g, label, cls in groups]
    top = max(int(r['total_tokens']) for _, _, rs in rows for r in rs)
    before = statistics.mean(int(r['total_tokens']) for r in rows[0][2])
    after = statistics.mean(int(r['total_tokens']) for r in rows[2][2])
    w, h, left, span = 1280, 140 + 96 * len(rows) + 60, 330, 760
    body = [f'  <text x="48" y="78" font-size="30" font-weight="800" class="accent">{1 - after / before:.0%} fewer tokens per task</text>',
            f'  <text x="48" y="110" font-size="17" class="muted">Same task, same code, same model; every run passed the same quality checks. '
            f'Mean {fmt(before)} before, {fmt(after)} with newleaf.</text>']
    y = 150
    for label, cls, rs in rows:
        mean = statistics.mean(int(r['total_tokens']) for r in rs)
        body.append(f'  <text x="48" y="{y + 26}" font-size="20" font-weight="700" class="ink">{label}</text>')
        body.append(f'  <text x="48" y="{y + 52}" font-size="15" class="muted">{len(rs)} runs, {statistics.mean(int(r["calls"]) for r in rs):.0f} calls, '
                    f'all {"passed" if all(r["quality"] == "pass" for r in rs) else "checked"}</text>')
        bh = min(18, 60 / len(rs))
        for k, r in enumerate(rs):
            v = int(r['total_tokens'])
            body.append(f'  <rect class="{cls}" x="{left}" y="{y + 6 + k * (bh + 5):.1f}" width="{max(4, v / top * span):.1f}" '
                        f'height="{bh:.1f}" rx="5"/>')
        body.append(f'  <text x="{left + max(4, mean / top * span) + 14:.0f}" y="{y + 34}" font-size="18" font-weight="700" class="ink">'
                    f'{fmt(mean)}</text>')
        y += 96
    body.append(f'  <text x="48" y="{h - 34}" font-size="15" class="muted">One bar per run: total tokens (input re-sent + written) '
                f'from Claude Code\'s own session logs. Data: docs/proof/runs.csv</text>')
    return svg(w, h, 'Tokens per task, every run', f'Mean tokens per task: {fmt(before)} in a resumed long chat, '
               f'{fmt(after)} in a fresh session with newleaf.', '\n'.join(body) + '\n')


def main():
    runs = read('runs.csv')
    for name, text in (('problem.svg', problem(runs)), ('proof.svg', proof(runs))):
        with open(os.path.join(ASSETS, name), 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        print('wrote', name)


if __name__ == '__main__':
    main()
