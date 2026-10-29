"""Verify a real Python breakpoint through the bundled debugpy DAP adapter."""
import argparse
import json
from pathlib import Path
import queue
import subprocess
import threading
import time

p = argparse.ArgumentParser()
p.add_argument('--python', required=True)
p.add_argument('--libs', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
out = Path(a.output).resolve()
out.mkdir(parents=True, exist_ok=True)
program = out / 'main.py'
program.write_text('print("start", flush=True)\nprint("SCHOOLLAB_PYTHON_DEBUG_OK", flush=True)\n', encoding='utf-8')
error_log = (out / 'stderr.log').open('wb')
proc = subprocess.Popen([a.python, '-I', '-c',
    'import sys,runpy;sys.path.insert(0,sys.argv.pop(1));runpy.run_module("debugpy.adapter",run_name="__main__")',
    a.libs], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=error_log)
messages = queue.Queue()
transcript = []

def reader():
    while True:
        headers = {}
        while True:
            line = proc.stdout.readline()
            if not line:
                return
            if line in (b'\r\n', b'\n'):
                break
            if b':' in line:
                key, value = line.split(b':', 1)
                headers[key.lower()] = value.strip()
        if b'content-length' in headers:
            messages.put(json.loads(proc.stdout.read(int(headers[b'content-length']))))

threading.Thread(target=reader, daemon=True).start()
seq = 0

def request(command, arguments):
    global seq
    seq += 1
    body = json.dumps({'seq':seq,'type':'request','command':command,'arguments':arguments}).encode('utf-8')
    proc.stdin.write(f'Content-Length: {len(body)}\r\n\r\n'.encode('ascii') + body)
    proc.stdin.flush()
    return seq

def until(predicate, seconds=40):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            message = messages.get(timeout=1)
        except queue.Empty:
            if proc.poll() is not None:
                raise RuntimeError(f'Adapter exited {proc.returncode}')
            continue
        transcript.append(message)
        if message.get('type') == 'response' and not message.get('success', False):
            raise RuntimeError(str(message))
        if predicate(message):
            return message
    raise RuntimeError('DAP response timed out')

try:
    initial = request('initialize', {'adapterID':'python','linesStartAt1':True,'columnsStartAt1':True,
        'pathFormat':'path','supportsRunInTerminalRequest':False})
    until(lambda m: m.get('request_seq') == initial)
    request('launch', {'name':'SchoolLab test','type':'debugpy','request':'launch','program':str(program),
        'python':[a.python], 'cwd':str(out), 'console':'internalConsole','redirectOutput':True,'justMyCode':True})
    until(lambda m: m.get('event') == 'initialized')
    bp = request('setBreakpoints', {'source':{'path':str(program)},'breakpoints':[{'line':2}]})
    reply = until(lambda m: m.get('request_seq') == bp)
    if not reply['body']['breakpoints'][0].get('verified'):
        raise RuntimeError('Breakpoint was not verified')
    request('configurationDone', {})
    stop = until(lambda m: m.get('event') == 'stopped')
    if stop['body']['reason'] != 'breakpoint':
        raise RuntimeError(f'Unexpected stop: {stop}')
    request('continue', {'threadId':stop['body']['threadId']})
    until(lambda m: m.get('event') == 'terminated')
    outputs = ''.join(m.get('body',{}).get('output','') for m in transcript if m.get('event') == 'output')
    if 'SCHOOLLAB_PYTHON_DEBUG_OK' not in outputs:
        raise RuntimeError('Expected debuggee output missing')
    print('PASS: Python 3.15 breakpoint verified, stopped, continued, printed expected output and terminated.')
finally:
    (out / 'messages.json').write_text(json.dumps(transcript, indent=2), encoding='utf-8')
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    error_log.close()
