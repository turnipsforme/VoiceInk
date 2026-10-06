#!/bin/bash
set -euo pipefail
ROOT="$HOME/VoiceInk-Dependencies/whisper.cpp"
REV=080bbbe85230f624f0b52127f1ae1218247989f9
if [[ -d "$ROOT/build-apple/whisper.xcframework" ]]; then
    echo 'Using existing whisper.xcframework'
    exit 0
fi
mkdir -p "$(dirname "$ROOT")"
if [[ ! -d "$ROOT/.git" ]]; then
    git clone https://github.com/ggerganov/whisper.cpp.git "$ROOT"
fi
git -C "$ROOT" fetch origin "$REV"
git -C "$ROOT" checkout --no-overwrite-ignore --detach "$REV"
cd "$ROOT"
# Reuse whisper's own framework packaging, but compile only the macOS slice.
python3 - <<'PY'
from pathlib import Path
s = Path('build-xcframework.sh').read_text()
preamble = s.split('echo "Building for iOS simulator..."')[0]
macos = s.split('echo "Building for macOS..."')[1].split('echo "Building for visionOS..."')[0]
suffix = '''
setup_framework_structure "build-macos" ${MACOS_MIN_OS_VERSION} "macos"
combine_static_libraries "build-macos" "Release" "macos" "false"
xcodebuild -create-xcframework \\
    -framework "$(pwd)/build-macos/framework/whisper.framework" \\
    -output "$(pwd)/build-apple/whisper.xcframework"
'''
Path('build-macos-local.sh').write_text(preamble + '\necho "Building for macOS..."\n' + macos + suffix)
PY
bash build-macos-local.sh
