#!/usr/bin/env python3
"""Fail closed if upstream removes or changes the local unlocked entitlement path."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
license_source = (root / 'VoiceInk/Features/Licensing/State/LicenseViewModel.swift').read_text()
updater_source = (root / 'VoiceInk/App/Updates/UpdaterViewModel.swift').read_text()
project = (root / 'VoiceInk.xcodeproj/project.pbxproj').read_text()
assert re.search(r'#if LOCAL_BUILD\s+isPersistentStateAvailable = true\s+licenseState = \.licensed', license_source), 'Local licence initialization changed; inspect before updating'
assert re.search(r'private func resolvedState\(at date: Date\) -> LicenseState\s*\{\s*#if LOCAL_BUILD\s*return \.licensed', license_source), 'Permanent local entitlement path changed'
assert re.search(r'var hasVerifiedLicense: Bool\s*\{\s*#if LOCAL_BUILD\s*true', license_source), 'Local verified entitlement path changed'
local_updater = updater_source.split('#if LOCAL_BUILD', 1)[1].split('\n#else\nimport Sparkle', 1)[0]
assert 'SPUStandardUpdaterController' not in local_updater
assert 'VoiceInkLocalUpdate' in local_updater
assert 'releases/latest' in local_updater
assert 'PRODUCT_BUNDLE_IDENTIFIER = com.wren.VoiceInk;' in project
assert 'LOCAL_BUILD' in (root / 'local/build-voiceink.sh').read_text()
assert 'SUFeedURL' in (root / 'local/build-voiceink.sh').read_text()
print('Verified: permanent local Pro entitlement, source-only updater, and compatible identity')
