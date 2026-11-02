#!/usr/bin/env python3
"""Real, interactive Claude Code in real terminals: several sessions side by side
in one throwaway folder, on different work. Proves no session gets another's note
and that opening a session leaves a running one alone.

    python tests/two_sessions.py [plugin dir to test instead of the installed plugin]

Needs a login; costs about a dozen small Haiku calls (NEWLEAF_SMOKE_MODEL picks
another model). Linux and macOS use a pty, Windows a ConPTY. Only touches the
processes it starts and the folder it makes.
"""
import glob
import json
import os
import secrets
import shutil
import sys
import tempfile
import threading
import time

MODEL = os.environ.get('NEWLEAF_SMOKE_MODEL', 'haiku')
CR, DOWN = bytes([13]), bytes([27, 91, 66])


class PosixTerm:
    def __init__(self, argv, cwd, env):
        import fcntl
        import pty
        import struct
        import termios
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd)
            os.execvpe(argv[0], argv, env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))

    def read(self):
        return os.read(self.fd, 65536)

    def write(self, data):
        os.write(self.fd, data)

    def alive(self):
        try:
            return os.waitpid(self.pid, os.WNOHANG)[0] == 0
        except OSError:
            return False

    def kill(self):
        try:
            os.kill(self.pid, 9)
            os.waitpid(self.pid, 0)
        except OSError:
            pass


class WindowsTerm:
    def __init__(self, argv, cwd, env):
        import ctypes as c
        import ctypes.wintypes as w
        import subprocess
        self.c, self.w = c, w
        k = self.k = c.WinDLL('kernel32', use_last_error=True)
        H = w.HANDLE

        class COORD(c.Structure):
            _fields_ = [('X', w.SHORT), ('Y', w.SHORT)]

        class STARTUPINFOW(c.Structure):
            _fields_ = [('cb', w.DWORD), ('lpReserved', w.LPWSTR), ('lpDesktop', w.LPWSTR), ('lpTitle', w.LPWSTR),
                        ('dwX', w.DWORD), ('dwY', w.DWORD), ('dwXSize', w.DWORD), ('dwYSize', w.DWORD),
                        ('dwXCountChars', w.DWORD), ('dwYCountChars', w.DWORD), ('dwFillAttribute', w.DWORD),
                        ('dwFlags', w.DWORD), ('wShowWindow', w.WORD), ('cbReserved2', w.WORD),
                        ('lpReserved2', c.c_void_p), ('hStdInput', H), ('hStdOutput', H), ('hStdError', H)]

        class STARTUPINFOEXW(c.Structure):
            _fields_ = [('StartupInfo', STARTUPINFOW), ('lpAttributeList', c.c_void_p)]

        class PROCESS_INFORMATION(c.Structure):
            _fields_ = [('hProcess', H), ('hThread', H), ('dwProcessId', w.DWORD), ('dwThreadId', w.DWORD)]

        k.CreatePipe.argtypes = [c.POINTER(H), c.POINTER(H), c.c_void_p, w.DWORD]
        k.CreatePseudoConsole.argtypes = [COORD, H, H, w.DWORD, c.POINTER(H)]
        k.CreatePseudoConsole.restype = c.c_long
        k.ClosePseudoConsole.argtypes = [H]
        k.InitializeProcThreadAttributeList.argtypes = [c.c_void_p, w.DWORD, w.DWORD, c.POINTER(c.c_size_t)]
        k.UpdateProcThreadAttribute.argtypes = [c.c_void_p, w.DWORD, c.c_size_t, c.c_void_p, c.c_size_t, c.c_void_p, c.c_void_p]
        k.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, c.c_void_p, c.c_void_p, w.BOOL, w.DWORD, c.c_void_p, w.LPCWSTR,
                                     c.c_void_p, c.POINTER(PROCESS_INFORMATION)]
        k.ReadFile.argtypes = [H, c.c_void_p, w.DWORD, c.POINTER(w.DWORD), c.c_void_p]
        k.WriteFile.argtypes = [H, c.c_void_p, w.DWORD, c.POINTER(w.DWORD), c.c_void_p]
        k.WaitForSingleObject.argtypes = [H, w.DWORD]
        k.TerminateProcess.argtypes = [H, w.UINT]
        k.CloseHandle.argtypes = [H]

        in_read, self.in_write, self.out_read, out_write = H(), H(), H(), H()
        if not k.CreatePipe(c.byref(in_read), c.byref(self.in_write), None, 0) or \
           not k.CreatePipe(c.byref(self.out_read), c.byref(out_write), None, 0):
            raise OSError('CreatePipe failed')
        self.pc = H()
        hr = k.CreatePseudoConsole(COORD(120, 40), in_read, out_write, 0, c.byref(self.pc))
        if hr != 0:
            raise OSError(f'CreatePseudoConsole: {hr:#x}')

        size = c.c_size_t()
        k.InitializeProcThreadAttributeList(None, 1, 0, c.byref(size))
        self.attrs = c.create_string_buffer(size.value)
        if not k.InitializeProcThreadAttributeList(self.attrs, 1, 0, c.byref(size)):
            raise OSError('InitializeProcThreadAttributeList failed')
        if not k.UpdateProcThreadAttribute(self.attrs, 0, 0x00020016, self.pc.value, c.sizeof(H), None, None):
            raise OSError('UpdateProcThreadAttribute failed')

        si = STARTUPINFOEXW()
        si.StartupInfo.cb = c.sizeof(STARTUPINFOEXW)
        si.StartupInfo.dwFlags = 0x100  # our own stdio may be pipes: the child must not inherit them
        si.lpAttributeList = c.cast(self.attrs, c.c_void_p)
        pi = PROCESS_INFORMATION()
        nul = chr(0)
        block = ''.join(f'{key}={env[key]}{nul}' for key in sorted(env)) + nul
        envbuf = c.create_unicode_buffer(block, len(block) + 1)
        cmd = c.create_unicode_buffer(subprocess.list2cmdline(argv))
        if not k.CreateProcessW(None, cmd, None, None, False, 0x00080000 | 0x00000400, envbuf, cwd, c.byref(si), c.byref(pi)):
            raise OSError(f'CreateProcessW: {c.get_last_error()}')
        self.proc = pi.hProcess
        k.CloseHandle(pi.hThread)
        k.CloseHandle(in_read)
        k.CloseHandle(out_write)

    def read(self):
        buf = self.c.create_string_buffer(65536)
        got = self.w.DWORD()
        if not self.k.ReadFile(self.out_read, buf, 65536, self.c.byref(got), None):
            return b''
        return buf.raw[:got.value]

    def write(self, data):
        got = self.w.DWORD()
        self.k.WriteFile(self.in_write, data, len(data), self.c.byref(got), None)

    def alive(self):
        return self.k.WaitForSingleObject(self.proc, 0) == 258

    def kill(self):
        self.k.TerminateProcess(self.proc, 1)
        self.k.ClosePseudoConsole(self.pc)


class Session:
    def __init__(self, name, folder, plugin, extra=()):
        self.name, self.folder, self.file = name, folder, None
        self.buf, self.last = b'', time.time()
        exe = shutil.which('claude')
        if not exe:
            sys.exit('claude not found')
        argv = [exe, '--model', MODEL, *extra]
        if plugin:
            argv += ['--plugin-dir', plugin]
        env = {k: v for k, v in os.environ.items()
               if not k.startswith('CLAUDE') or k in ('CLAUDE_CODE_GIT_BASH_PATH', 'CLAUDE_CONFIG_DIR')}
        env.setdefault('TERM', 'xterm-256color')
        self.term = (WindowsTerm if os.name == 'nt' else PosixTerm)(argv, folder, env)
        threading.Thread(target=self._pump, daemon=True).start()
        self.settle()
        if b'trust' in self.buf.lower():
            time.sleep(1)
            self.term.write(DOWN)
            time.sleep(0.8)
            self.term.write(CR)
            self.buf = b''
            self.settle()

    def _pump(self):
        while True:
            try:
                data = self.term.read()
            except OSError:
                return
            if not data:
                return
            self.buf += data
            self.last = time.time()

    def settle(self, quiet=4, limit=60):
        start = time.time()
        while time.time() - start < limit:
            if self.buf and time.time() - self.last > quiet:
                return
            time.sleep(0.3)

    def send(self, text):
        self.term.write(text.encode('utf-8'))
        time.sleep(0.8)
        self.term.write(CR)

    def screen(self):
        return bytes(b for b in self.buf if 32 <= b < 127)[-300:].decode('ascii')


def transcripts(folder):
    name = os.path.basename(folder)
    root = os.environ.get('CLAUDE_CONFIG_DIR') or os.path.expanduser('~/.claude')
    return glob.glob(os.path.join(root, 'projects', f'*{name}*', '*.jsonl'))


def entries(path):
    out = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def reply_after(session, tag, limit=240):
    """The text of the session's reply to the prompt carrying tag, once its turn has ended."""
    start = time.time()
    while time.time() - start < limit:
        for path in transcripts(session.folder):
            es = entries(path)
            at = next((i for i, e in enumerate(es) if e.get('type') == 'user' and tag in json.dumps(e.get('message'))), None)
            if at is None:
                continue
            session.file = path
            text, done = [], False
            for e in es[at + 1:]:
                if e.get('type') == 'assistant':
                    for block in (e.get('message') or {}).get('content') or []:
                        if isinstance(block, dict) and block.get('type') == 'text':
                            text.append(block.get('text', ''))
                if e.get('type') == 'system' and e.get('subtype') in ('turn_duration', 'stop_hook_summary'):
                    done = True
            if done and text:
                return ' '.join(text)
        time.sleep(2)
    return f'(no reply in {limit}s; screen: {session.screen()})'


def ask(session, question):
    tag = 'Q' + secrets.token_hex(4)
    session.send(f'{tag}: {question}')
    return reply_after(session, tag)


def main():
    plugin = sys.argv[1] if len(sys.argv) > 1 else None
    if plugin:
        plugin = os.path.abspath(plugin)
    base = tempfile.mkdtemp(prefix='newleaf-two-')
    name = 'nle2e' + secrets.token_hex(5)
    folder = os.path.join(base, name)
    os.makedirs(folder)
    fails = []
    sessions = []

    def check(label, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + label + ('' if ok else f'  ({detail[:300]})'), flush=True)
        if not ok:
            fails.append(label)

    def open_session(label, extra=()):
        s = Session(label, folder, plugin, extra)
        sessions.append(s)
        return s

    def save_note(session, marker, limit=300):
        session.send(f'/newleaf:newleaf The exact next step is {marker}')
        start = time.time()
        while time.time() - start < limit:
            for path in glob.glob(os.path.join(folder, '.newleaf', 'notes', '*.md')):
                with open(path, encoding='utf-8', errors='replace') as f:
                    if marker in f.read():
                        session.settle(quiet=3, limit=30)
                        return True
            time.sleep(2)
        return False

    next_section = "Use no tools. Reply with the full text of the '## Next' section of the handoff note in your context. If no handoff note's text is in your context, reply NONE."
    mark_a, mark_b = 'MARKA' + secrets.token_hex(3), 'MARKB' + secrets.token_hex(3)
    try:
        # a script, not a bare sleep: Claude Code steers models away from a foreground sleep
        with open(os.path.join(folder, 'slow.sh'), 'w', newline='') as f:
            f.write('sleep 30' + chr(10) + 'echo SLOW-DONE' + chr(10))
        a = open_session('A', ['--allowedTools', 'Bash(bash slow.sh)'])
        b = open_session('B')
        check('A and B start side by side in one folder', a.term.alive() and b.term.alive(), a.screen() + ' / ' + b.screen())
        check("A's /newleaf saves A's note", save_note(a, mark_a), a.screen())
        check("B's /newleaf saves B's note", save_note(b, mark_b), b.screen())

        a.send('/clear')
        a.settle(quiet=3, limit=30)
        r = ask(a, next_section)
        check("A's /clear gets A's note, not B's (B saved last)", mark_a in r and mark_b not in r, r)
        b.send('/clear')
        b.settle(quiet=3, limit=30)
        r = ask(b, next_section)
        check("B's /clear gets B's note", mark_b in r and mark_a not in r, r)

        a.send('/compact')
        start, compacted = time.time(), False
        while time.time() - start < 240 and not compacted:
            compacted = a.file and any(e.get('subtype') == 'compact_boundary' for e in entries(a.file))
            time.sleep(3)
        check('A compacts', bool(compacted), a.screen())
        a.settle(quiet=3, limit=30)
        r = ask(a, next_section)
        check("A's compaction brings back A's note, not B's", mark_a in r and mark_b not in r, r)

        c = open_session('C')
        r = ask(c, next_section)
        check('a brand-new session does not get either note', mark_a not in r and mark_b not in r, r)
        r = ask(c, "Continue the work from the handoff note you were told about: read that file and reply with only the text of its '## Next' section.")
        check('asked to continue, it reads the latest note', mark_b in r, r)

        # opening a session while another is mid-command
        tag = 'Q' + secrets.token_hex(4)
        a.send(f'{tag}: Run exactly this one bash command in the foreground and wait for it: bash slow.sh . Then reply with only the word it printed.')
        time.sleep(6)
        d = open_session('D')
        r = ask(d, 'Reply with only the word READY.')
        check('a new session opens and answers while A is mid-command', 'READY' in r, r)
        r = reply_after(a, tag)
        check('A finishes its command, untouched', 'SLOW-DONE' in r and a.term.alive(), r)
        check('every session is still alive', all(s.term.alive() for s in sessions), ','.join(s.name for s in sessions if not s.term.alive()))
    finally:
        for s in sessions:
            s.term.kill()
        time.sleep(1)
        root = os.environ.get('CLAUDE_CONFIG_DIR') or os.path.expanduser('~/.claude')
        for path in glob.glob(os.path.join(root, 'projects', f'*{name}*')):
            shutil.rmtree(path, ignore_errors=True)
        shutil.rmtree(base, ignore_errors=True)
    print(f'{len(fails)} failed')
    return len(fails)


if __name__ == '__main__':
    sys.exit(main())
