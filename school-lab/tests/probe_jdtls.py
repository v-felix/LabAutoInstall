"""Start the packaged Java language/debug server using a real JDK; no VS Code UI."""
import argparse
import json
from pathlib import Path
import queue
import subprocess
import threading
import time

p = argparse.ArgumentParser()
p.add_argument('--java', required=True)
p.add_argument('--extensions', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
output = Path(a.output).resolve()
output.mkdir(parents=True, exist_ok=True)
extensions = Path(a.extensions)
server = next(extensions.glob('redhat.java-*/server'))
launcher = next(server.glob('plugins/org.eclipse.equinox.launcher_*.jar'))
debug_bundle = next(extensions.glob('vscjava.vscode-java-debug-*/server/com.microsoft.java.debug.plugin-*.jar'))
workspace = output / 'workspace'
workspace.mkdir(exist_ok=True)
(workspace / 'LabHello.java').write_text('public class LabHello { public static void main(String[] args) { System.out.println("OK"); } }', encoding='utf-8')
messages = queue.Queue()
stderr = (output / 'stderr.log').open('wb')
proc = subprocess.Popen([a.java, '-Declipse.application=org.eclipse.jdt.ls.core.id1',
    '-Declipse.product=org.eclipse.jdt.ls.core.product', '-Dosgi.bundles.defaultStartLevel=4',
    '-Xmx512m', '--add-modules=ALL-SYSTEM', '--add-opens', 'java.base/java.util=ALL-UNNAMED',
    '--add-opens', 'java.base/java.lang=ALL-UNNAMED', '-jar', str(launcher.resolve()),
    '-configuration', str((server / 'config_win').resolve()), '-data', str(output / 'data')],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr)

def reader():
    try:
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
                body = proc.stdout.read(int(headers[b'content-length']))
                messages.put(json.loads(body))
    except Exception as exc:
        messages.put({'probe_error': str(exc)})

threading.Thread(target=reader, daemon=True).start()

def send(value):
    body = json.dumps(value).encode('utf-8')
    proc.stdin.write(f'Content-Length: {len(body)}\r\n\r\n'.encode('ascii') + body)
    proc.stdin.flush()

try:
    send({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'processId':None,
        'rootUri':workspace.as_uri(), 'workspaceFolders':[{'uri':workspace.as_uri(),'name':'SchoolLab'}],
        'capabilities':{}, 'initializationOptions':{'bundles':[str(debug_bundle.resolve())],
        'settings':{'java':{'import':{'maven':{'enabled':False},'gradle':{'enabled':False}}}}}}})
    deadline = time.monotonic() + 80
    initialized = False
    transcript = []
    while time.monotonic() < deadline:
        try:
            message = messages.get(timeout=1)
        except queue.Empty:
            if proc.poll() is not None:
                raise RuntimeError(f'Language server exited: {proc.returncode}')
            continue
        transcript.append(message)
        if message.get('id') == 1 and 'result' in message:
            initialized = True
            break
        if message.get('id') == 1 and 'error' in message:
            raise RuntimeError(str(message['error']))
        if 'id' in message and 'method' in message:
            send({'jsonrpc':'2.0','id':message['id'],'result':None})
    (output / 'messages.json').write_text(json.dumps(transcript, indent=2), encoding='utf-8')
    if not initialized:
        raise RuntimeError('Java language server initialize timed out')
    send({'jsonrpc':'2.0','method':'initialized','params':{}})
    send({'jsonrpc':'2.0','id':2,'method':'shutdown','params':None})
    print('PASS: packaged Java language server initialized under selected JDK with Java debugger bundle.')
finally:
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    stderr.close()
