#!/usr/bin/env python3
"""Builds docs/newleaf-guide.pdf from docs/guide/guide.html with a Chromium
browser (Edge, Chrome or Chromium) in headless mode. The figures go in as
light-palette copies (their dark-mode CSS taken out), so print stays light.
    python docs/guide/build.py
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
CANDIDATES = [
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
]


def browser():
    for name in ('msedge', 'google-chrome', 'chromium', 'chromium-browser', 'chrome'):
        if shutil.which(name):
            return shutil.which(name)
    return next((p for p in CANDIDATES if os.path.exists(p)), None)


def main():
    exe = browser()
    if not exe:
        sys.exit('no Chromium browser found (Edge, Chrome or Chromium)')
    img = os.path.join(HERE, 'img')
    os.makedirs(img, exist_ok=True)
    for name in ('banner', 'problem', 'flow', 'proof'):
        with open(os.path.join(DOCS, 'assets', name + '.svg'), encoding='utf-8') as f:
            svg = re.sub(r'@media \(prefers-color-scheme: dark\) \{.*?\n    \}\n', '', f.read(), flags=re.S)
        with open(os.path.join(img, name + '.svg'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(svg)
    out = os.path.join(DOCS, 'newleaf-guide.pdf')
    src = 'file:///' + os.path.join(HERE, 'guide.html').replace(os.sep, '/').lstrip('/')
    subprocess.run([exe, '--headless=new', '--disable-gpu', '--no-pdf-header-footer', f'--print-to-pdf={out}', src],
                   check=True, capture_output=True, timeout=120)
    print('wrote', out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main()
