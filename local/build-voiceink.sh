#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${VOICEINK_UPSTREAM_TAG:-v2.21}"
./local/verify-source.py
./local/build-whisper.sh
VERSION="${TAG#v}"
BUILD="$(python3 - "$VERSION" <<'PY'
import sys
parts = [int(x) for x in sys.argv[1].split('.')]
print(parts[0] * 100 + parts[1])
PY
)"
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
    -derivedDataPath "$PWD/.local-build" -xcconfig LocalBuild.xcconfig \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD ENABLE_NATIVE_SPEECH_ANALYZER' \
    -skipPackagePluginValidation -skipMacroValidation build
APP="$PWD/.local-build/Build/Products/Release/VoiceInk.app"
ditto local/VoiceInkLocalUpdate.command "$APP/Contents/Resources/VoiceInkLocalUpdate.command"
chmod +x "$APP/Contents/Resources/VoiceInkLocalUpdate.command"
python3 - "$APP" "$TAG" <<'PY'
import json, plistlib, subprocess, sys
from pathlib import Path
app, tag = Path(sys.argv[1]), sys.argv[2]
p = app / 'Contents/Info.plist'
info = plistlib.loads(p.read_bytes())
for k in ['SUFeedURL', 'SUPublicEDKey', 'SUEnableInstallerLauncherService', 'SUScheduledCheckInterval']:
    info.pop(k, None)
info['SUEnableAutomaticChecks'] = False
info['VoiceInkLocalUnlocked'] = True
info['VoiceInkUpdatePolicy'] = 'source-rebuild-only'
info['VoiceInkUpstreamTag'] = tag
info['VoiceInkSourceCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
assert info['CFBundleIdentifier'] == 'com.wren.VoiceInk'
assert info['CFBundleName'] == 'VoiceInk'
p.write_bytes(plistlib.dumps(info))
manifest = {k: info[k] for k in ['VoiceInkUpstreamTag', 'VoiceInkSourceCommit', 'VoiceInkUpdatePolicy']}
manifest['localUnlocked'] = True
manifest['bundleIdentifier'] = info['CFBundleIdentifier']
manifest['version'] = info['CFBundleShortVersionString']
manifest['build'] = info['CFBundleVersion']
(app / 'Contents/Resources/VoiceInkLocalBuild.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
codesign --force --sign - --options runtime --entitlements VoiceInk/VoiceInk.local.entitlements "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p .local-build/dist
ditto -c -k --sequesterRsrc --keepParent "$APP" .local-build/dist/VoiceInk.zip
shasum -a 256 .local-build/dist/VoiceInk.zip > .local-build/dist/VoiceInk.zip.sha256
cp "$APP/Contents/Resources/VoiceInkLocalBuild.json" .local-build/dist/
