#!/usr/bin/env python3
"""Runs newleaf's Codex hooks on Windows exactly the way Codex does:

    cmd.exe /C "<commandWindows>"

(codex-rs/hooks/src/engine/command_runner.rs: the shell program, arg "/C", then
raw_arg of the command line wrapped in quotes). The command line is handed to
CreateProcess as is, with a made-up project, transcript and reply, and the
script checks what comes back, byte for byte.   python tests/windows_cmd.py
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    if os.name != 'nt':
        print('skipped: Windows only')
        return 0
    with open(os.path.join(ROOT, 'hooks', 'codex-hooks.json'), encoding='utf-8') as f:
        hooks = json.load(f)['hooks']
    windows = {event: groups[0]['hooks'][0]['commandWindows'] for event, groups in hooks.items()}
    fails = 0

    def check(name, ok):
        nonlocal fails
        print(('ok   ' if ok else 'FAIL ') + name)
        fails += 0 if ok else 1

    with tempfile.TemporaryDirectory() as tmp:
        proj, home, data = (os.path.join(tmp, d) for d in ('proj', 'home', 'data'))
        for d in (os.path.join(proj, '.newleaf'), os.path.join(home, '.claude'), data):
            os.makedirs(d)
        env = {k: v for k, v in os.environ.items() if k != 'CLAUDE_PROJECT_DIR'}
        env.update(CLAUDE_PLUGIN_ROOT=ROOT, CLAUDE_PLUGIN_DATA=data, HOME=home, USERPROFILE=home)

        def run(event, payload):
            line = 'cmd.exe /C "' + windows[event] + '"'
            r = subprocess.run(line, input=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
                               capture_output=True, env=env, timeout=120)
            return r.returncode, r.stdout

        note = '---\nwritten: now\nbranch: none\nhead: none\n---\n## Next\nship é 🍃\n'
        with open(os.path.join(proj, '.newleaf', 'handoff.md'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(note)
        code, out = run('SessionStart', {'cwd': proj, 'source': 'startup', 'hook_event_name': 'SessionStart'})
        check('SessionStart: exit 0', code == 0)
        check('SessionStart: the rules and the note, bytes intact', b'Lean working rules' in out and 'ship é 🍃'.encode('utf-8') in out)

        reply = 'Done.\n<newleaf-note>\n---\nwritten: now\nbranch: none\nhead: none\n---\n## Next\nsaved é 🍃\n</newleaf-note>\n'
        code, out = run('Stop', {'cwd': proj, 'hook_event_name': 'Stop', 'last_assistant_message': reply, 'stop_hook_active': False})
        check('Stop: exit 0 and JSON out', code == 0 and json.loads(out.decode('utf-8')).get('systemMessage', '').startswith('newleaf: note saved'))
        with open(os.path.join(proj, '.newleaf', 'handoff.md'), encoding='utf-8') as f:
            check('Stop: the note saved, bytes intact', 'saved é 🍃' in f.read())

        tr = os.path.join(tmp, 'rollout.jsonl')

        def tok(n):
            usage = {'input_tokens': n, 'cached_input_tokens': 0, 'output_tokens': 9, 'reasoning_output_tokens': 0, 'total_tokens': n}
            return json.dumps({'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {
                'total_token_usage': usage, 'last_token_usage': usage, 'model_context_window': 272000}}}, separators=(',', ':'))
        with open(tr, 'w', encoding='utf-8', newline='\n') as f:
            f.write(tok(40000) + '\n' + tok(85000) + '\n')
        code, out = run('UserPromptSubmit', {'session_id': 'w1', 'transcript_path': tr, 'cwd': proj,
                                             'hook_event_name': 'UserPromptSubmit', 'prompt': 'hi'})
        check('UserPromptSubmit: the guard speaks at 2x a Codex chat', code == 0 and b'85k' in out and b'2x its start (40k)' in out)
    print(f'{fails} failed')
    return fails


if __name__ == '__main__':
    sys.exit(main())
