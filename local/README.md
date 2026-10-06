# VoiceInk local unlocked build

VoiceInk remains named **VoiceInk** and uses the installed application's `com.wren.VoiceInk` identity. Upstream's GPL-licensed `LOCAL_BUILD` configuration permanently enables local Pro functionality without a license key or trial expiration. It does not provide paid hosted API access; your own provider credentials are still required. Local builds disable CloudKit sync, as upstream documents in `BUILDING.md`.

## Updates

Use **VoiceInk → Check for Updates… → Rebuild & Install**. This opens Terminal and runs:

```sh
~/Developer/VoiceInk-local/local/update-voiceink.sh --update
```

The default route compiles your modified source on the fork's GitHub Actions macOS runner. Full Xcode is not required on your Mac, but authenticated `gh`, network access, and Actions availability are. It is a source build installed locally, not compilation on your Mac. No official upstream app binary is installed.

If full Xcode and CMake are available locally, compile on this Mac instead:

```sh
~/Developer/VoiceInk-local/local/update-voiceink.sh --local
```

The updater merges stable upstream releases, keeps the local changes, checks permanent access guards, and stops without replacing the app if a merge or build fails. Upstream structural changes can require manual patch maintenance; this intentionally fails closed rather than restoring paid licensing. It never force-kills VoiceInk; finish any recording first.

## Data and recovery

The installer preserves preferences, modes, SwiftData databases, recordings, and downloaded models in their existing locations. Before each replacement it quits VoiceInk gracefully and creates a private backup at:

```
~/Library/Application Support/VoiceInkLocalBuild/Backups/<timestamp>/
```

Backups include the old app, exported preferences, VoiceInk application support, and FluidAudio support/cache models. APFS clone copies are used where possible. Login Keychain contents remain in place; upstream may migrate legacy API keys from preferences into the login Keychain on first launch.

To revert just the executable, quit VoiceInk and copy the backup's `VoiceInk.app` to `/Applications/VoiceInk.app`. If a version changed the database schema, also restore the matching support-directory backups and import that backup's preferences with `defaults import com.wren.VoiceInk <backup>/com.wren.VoiceInk.plist`. Restoring data replaces newer data, so preserve it first. Do not overwrite model folders unless needed.

Ad-hoc signing is used because no Developer ID is configured. macOS can request microphone, accessibility, and other permissions again after source rebuilds. The app is not notarized. Artifact download requires a successful run on this fork, matching source commit and stable tag, valid SHA-256 checksum, correct bundle identity, and strict code-signature verification.

## Development

The original working tree at `~/VoiceInk` is not used or modified. Source lives at `~/Developer/VoiceInk-local` on branch `local-unlocked`, with `origin` pointing to the fork and `upstream` to `Beingpax/VoiceInk`. The dependency builder uses a pinned whisper.cpp revision and compiles only the macOS framework slice. Licensing and updater changes are guarded by `local/verify-source.py`.
