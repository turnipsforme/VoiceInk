#!/usr/bin/env python3
"""Back up app and local data, then replace only the application bundle."""
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time

home = Path.home()
app = Path(sys.argv[1]).resolve()
expected_commit = sys.argv[2] if len(sys.argv) > 2 else None
installed = Path('/Applications/VoiceInk.app')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info.get('CFBundleIdentifier') == 'com.wren.VoiceInk', 'Unexpected app identity'
assert info.get('CFBundleName') == 'VoiceInk', 'Unexpected app name'
assert info.get('VoiceInkLocalUnlocked') is True, 'Not an unlocked local build'
assert info.get('VoiceInkUpdatePolicy') == 'source-rebuild-only', 'Unsafe update policy'
assert 'SUFeedURL' not in info, 'Official update feed is still configured'
assert info.get('SUEnableAutomaticChecks') is False
assert (app / 'Contents/Resources/VoiceInkLocalUpdate.command').is_file()
if expected_commit:
    assert info.get('VoiceInkSourceCommit') == expected_commit, 'Artifact source commit mismatch'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
subprocess.run(['lipo', '-verify_arch', 'arm64', str(app / 'Contents/MacOS/VoiceInk')], check=True)
if installed.exists():
    old = plistlib.loads((installed / 'Contents/Info.plist').read_bytes())
    assert old.get('CFBundleIdentifier') == info['CFBundleIdentifier'], 'Installed identity changed; manual migration required'

# Graceful termination: never force-kill an active recording or a refusing app.
running = subprocess.run(['pgrep', '-x', 'VoiceInk'], capture_output=True, text=True).returncode == 0
if running:
    subprocess.run(['osascript', '-e', 'tell application id "com.wren.VoiceInk" to quit'], check=True, timeout=45)
    for _ in range(30):
        if subprocess.run(['pgrep', '-x', 'VoiceInk'], capture_output=True).returncode != 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError('VoiceInk is still running; installation stopped without replacing it')

stamp = datetime.datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
backup = home / 'Library/Application Support/VoiceInkLocalBuild/Backups' / stamp
backup.mkdir(parents=True, exist_ok=False, mode=0o700)
os.chmod(backup, 0o700)

def copy_tree(source, target):
    if source.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        # APFS clone avoids duplicating model storage when supported; ditto is the fallback.
        result = subprocess.run(['/bin/cp', '-cR', str(source), str(target)], capture_output=True)
        if result.returncode:
            subprocess.run(['/usr/bin/ditto', str(source), str(target)], check=True)

copy_tree(installed, backup / 'VoiceInk.app')
prefs = backup / 'com.wren.VoiceInk.plist'
subprocess.run(['/usr/bin/defaults', 'export', 'com.wren.VoiceInk', str(prefs)], check=True, capture_output=True)
os.chmod(prefs, 0o600)
for relative in [
    'Library/Application Support/com.prakashjoshipax.VoiceInk',
    'Library/Application Support/VoiceInk',
    'Library/Application Support/FluidAudio',
    'Library/Caches/FluidAudio',
]:
    copy_tree(home / relative, backup / relative)
(backup / 'backup.json').write_text(json.dumps({
    'installedApp': str(installed), 'bundleIdentifier': info['CFBundleIdentifier'],
    'newVersion': info['CFBundleShortVersionString'],
    'sourceCommit': info.get('VoiceInkSourceCommit'),
    'dataPolicy': 'Existing preferences, stores, recordings and models left in place',
}, indent=2) + '\n')

stage = Path('/Applications/.VoiceInk-local-staging-' + stamp + '.app')
assert not stage.exists()
subprocess.run(['/usr/bin/ditto', str(app), str(stage)], check=True)
subprocess.run(['/usr/bin/xattr', '-dr', 'com.apple.quarantine', str(stage)], capture_output=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
previous = Path('/Applications/.VoiceInk-local-previous-' + stamp + '.app')
try:
    if installed.exists():
        installed.rename(previous)
    stage.rename(installed)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(installed)], check=True)
except BaseException:
    if previous.exists():
        if installed.exists():
            shutil.rmtree(installed)
        previous.rename(installed)
    if stage.exists():
        shutil.rmtree(stage)
    raise
if previous.exists():
    shutil.rmtree(previous)
print('Installed:', installed)
print('Backup:', backup)
print('Pro features enabled; existing settings, modes, history and models retained in place.')
subprocess.run(['/usr/bin/open', str(installed)], check=True)
