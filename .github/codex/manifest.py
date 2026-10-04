import hashlib
import json
import pathlib
import subprocess
import sys


def git(*args):
    return subprocess.check_output(['git', *args]).decode().strip()


files = {}
for record in subprocess.check_output(['git', 'ls-files', '-s', '-z']).split(b'\0'):
    if not record:
        continue
    metadata, filename = record.decode().split('\t', 1)
    mode, blob, stage = metadata.split()
    files[filename] = {'blob': blob, 'rawSHA256': hashlib.sha256(pathlib.Path(filename).read_bytes()).hexdigest()}
data = {'head': git('rev-parse', 'HEAD'), 'status': git('status', '--porcelain'), 'files': files}
pathlib.Path(sys.argv[1]).write_text(json.dumps(data, indent=2))
if len(sys.argv) > 2:
    previous = json.loads(pathlib.Path(sys.argv[2]).read_text())
    assert data == previous, [name for name in files if files[name] != previous['files'].get(name)]
assert not data['status'], data['status']
print(data['head'], len(files), 'tracked files; clean')
