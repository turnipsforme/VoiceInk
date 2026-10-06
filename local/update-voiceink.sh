#!/bin/bash
# Build only modified source. Never download or install upstream release binaries.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPO=turnipsforme/VoiceInk
BRANCH=local-unlocked
MODE="${1:---update}"
mkdir -p local/.work
if ! mkdir local/.update-lock 2>/dev/null; then
    echo 'Another updater may be running. No changes made.' >&2
    exit 1
fi
trap 'rmdir "$ROOT/local/.update-lock" 2>/dev/null || true' EXIT
command -v gh >/dev/null || { echo 'GitHub CLI is required: brew install gh'; exit 1; }
gh auth status >/dev/null
[[ "$(git branch --show-current)" == "$BRANCH" ]] || { echo "Use branch $BRANCH"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Source has uncommitted changes. Preserve or commit them before updating; app unchanged.'; exit 1; }
[[ "$(git remote get-url origin)" == "https://github.com/$REPO.git" ]] || { echo 'Unexpected fork remote'; exit 1; }

if [[ "$MODE" == '--install-run' ]]; then
    RUN="${2:?Supply a successful workflow run ID}"
    [[ "$RUN" =~ ^[0-9]+$ ]] || exit 1
    TAG="$(cat local/upstream-tag)"
else
    [[ "$MODE" == '--update' || "$MODE" == '--local' ]] || { echo 'Usage: update-voiceink.sh [--update | --local | --install-run ID]'; exit 1; }
    git fetch origin "$BRANCH"
    git merge --ff-only "origin/$BRANCH"
    RELEASE="$(gh api repos/Beingpax/VoiceInk/releases/latest)"
    TAG="$(printf '%s' "$RELEASE" | python3 -c 'import json,sys,re; r=json.load(sys.stdin); assert not r["draft"] and not r["prerelease"]; t=r["tag_name"]; assert re.fullmatch(r"v[0-9]+(?:\.[0-9]+){1,2}",t); print(t)')"
    CURRENT="$(cat local/upstream-tag)"
    if [[ "$TAG" != "$CURRENT" ]]; then
        git fetch upstream "refs/tags/$TAG:refs/tags/$TAG"
        if ! git merge --no-commit --no-ff "$TAG"; then
            git merge --abort
            echo 'Upstream conflicts with the local patches. Resolve and review them before rebuilding; installed VoiceInk is unchanged.' >&2
            exit 1
        fi
        if ! ./local/verify-source.py; then
            git merge --abort
            echo 'Upstream changed the unlocked access safeguards; installed VoiceInk is unchanged.' >&2
            exit 1
        fi
        printf '%s\n' "$TAG" > local/upstream-tag
        git add local/upstream-tag
        git commit -m "Merge stable upstream $TAG; preserve unlocked source updater"
        git push origin "$BRANCH"
    else
        ./local/verify-source.py
        git push origin "$BRANCH"
    fi
    if [[ "$MODE" == '--local' ]]; then
        xcodebuild -version
        VOICEINK_UPSTREAM_TAG="$TAG" ./local/build-voiceink.sh
        python3 local/install-voiceink.py .local-build/Build/Products/Release/VoiceInk.app "$(git rev-parse HEAD)"
        exit 0
    fi
    REQUEST="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    gh workflow run local-unlocked.yml --repo "$REPO" --ref "$BRANCH" -f upstream_tag="$TAG" -f request_id="$REQUEST"
    RUN=''
    for _ in {1..60}; do
        RUN="$(gh run list --repo "$REPO" --workflow local-unlocked.yml --branch "$BRANCH" --event workflow_dispatch --limit 50 --json databaseId,displayTitle | python3 -c 'import json,sys; key=sys.argv[1]; r=[str(x["databaseId"]) for x in json.load(sys.stdin) if x["displayTitle"].endswith(key)]; print(r[0] if r else "")' "$REQUEST")"
        [[ -n "$RUN" ]] && break
        sleep 5
    done
    [[ -n "$RUN" ]] || { echo 'Build dispatch could not be located; installed app unchanged.'; exit 1; }
    echo "Building modified source: https://github.com/$REPO/actions/runs/$RUN"
    gh run watch "$RUN" --repo "$REPO" --exit-status --interval 30
fi
EXPECTED="$(git rev-parse HEAD)"
gh run view "$RUN" --repo "$REPO" --json conclusion,headSha,headBranch,event,workflowName > local/.work/run.json
python3 - "$EXPECTED" <<'PY'
import json,sys
from pathlib import Path
r=json.loads(Path('local/.work/run.json').read_text())
assert r['conclusion']=='success', 'Build was not successful'
assert r['headSha']==sys.argv[1], 'Run does not match checked-out source'
assert r['headBranch']=='local-unlocked' and r['event']=='workflow_dispatch'
assert r['workflowName']=='Build VoiceInk Local'
PY
DEST="$ROOT/local/.work/run-$RUN-$(date +%s)"
mkdir -p "$DEST"
gh run download "$RUN" --repo "$REPO" --name VoiceInk-local-arm64 --dir "$DEST"
python3 - "$DEST" "$EXPECTED" "$TAG" <<'PY'
import hashlib,json,sys,zipfile
from pathlib import Path
p=Path(sys.argv[1]); archive=p/'VoiceInk.zip'
record=(p/'VoiceInk.zip.sha256').read_text().split()[0]
assert len(record)==64 and hashlib.sha256(archive.read_bytes()).hexdigest()==record, 'Archive checksum mismatch'
m=json.loads((p/'VoiceInkLocalBuild.json').read_text())
assert m['VoiceInkSourceCommit']==sys.argv[2] and m['VoiceInkUpstreamTag']==sys.argv[3]
assert m['localUnlocked'] is True and m['VoiceInkUpdatePolicy']=='source-rebuild-only'
assert m['bundleIdentifier']=='com.wren.VoiceInk'
with zipfile.ZipFile(archive) as z:
    for name in z.namelist():
        assert not name.startswith('/') and '..' not in Path(name).parts, 'Unsafe archive path'
        assert Path(name).parts[0] in ('VoiceInk.app','__MACOSX'), 'Unexpected archive content'
print('Verified artifact checksum and source provenance')
PY
/usr/bin/ditto -x -k "$DEST/VoiceInk.zip" "$DEST/extracted"
python3 local/install-voiceink.py "$DEST/extracted/VoiceInk.app" "$EXPECTED"
echo 'Future updates: use VoiceInk → Check for Updates…, or run this script again.'
