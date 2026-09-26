#!/usr/bin/env python3
"""CLI regression test using a temporary fixture key, never a production credential.

Apple signature/ticket commands are stubbed: this tests packaging and Sparkle
validation, not notarization or installation. All other commands run normally.
Set SPARKLE_BIN to a Sparkle distribution containing sign_update.
"""
import base64
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET

scripts = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='quickmotion-packaging-test-') as directory:
    root = Path(directory)
    key = root / 'fixture.key'
    key.write_text(base64.b64encode(os.urandom(32)).decode())
    key.chmod(0o600)
    # Derive only the public key; the fixture seed stays in the temporary directory.
    derive = root / 'derive.swift'
    derive.write_text('''import Foundation
import CryptoKit
let seed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: seed)!)
print(key.publicKey.rawRepresentation.base64EncodedString())
''')
    executable = root / 'derive'
    subprocess.run(['xcrun', 'swiftc', str(derive), '-module-cache-path', str(root/'module-cache'), '-o', str(executable)], check=True)
    public = subprocess.check_output([str(executable), str(key)], text=True).strip()
    mock = root / 'mock-bin'
    mock.mkdir()
    (mock / 'codesign').write_text('#!/bin/sh\nexit 0\n')
    (mock / 'xcrun').write_text('#!/bin/sh\nif [ "$1" = stapler ]; then exit 0; fi\nexec /usr/bin/xcrun "$@"\n')
    for file in mock.iterdir():
        file.chmod(0o700)
    app = root / 'QuickMotion.app'
    (app / 'Contents').mkdir(parents=True)
    info = {'CFBundleIdentifier': 'com.lucesumbrarum.quickmotion',
            'CFBundleShortVersionString': '1.0.4', 'CFBundleVersion': '104',
            'SUPublicEDKey': public, 'LSMinimumSystemVersion': '14.0'}
    plist = app / 'Contents/Info.plist'
    plist.write_bytes(plistlib.dumps(info))
    env = dict(os.environ, SPARKLE_KEY_FILE=str(key), PATH=str(mock)+':'+os.environ['PATH'])
    env.pop('SPARKLE_ACCOUNT', None)
    def invoke(output, version=None, environment=env):
        args = ['bash', str(scripts / 'sign-for-sparkle.sh'), str(app)]
        if version:
            args.append(version)
        return subprocess.run(args + ['--output', str(output)], env=environment,
                              capture_output=True, text=True)
    good = root / 'good'
    result = invoke(good)
    assert result.returncode == 0, 'Matching-key packaging failed (tool output suppressed)'
    item = ET.fromstring(result.stdout)
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    assert item.find(ns+'version').text == '104'
    enclosure = item.find('enclosure')
    archive = good / 'QuickMotion-1.0.4.zip'
    assert int(enclosure.attrib['length']) == archive.stat().st_size
    assert list(enclosure.attrib).count('length') == 1
    original = archive.read_bytes()
    assert invoke(good).returncode != 0 and archive.read_bytes() == original
    assert invoke(root/'version', '1.0.5').returncode != 0
    conflict = dict(env, SPARKLE_ACCOUNT='must-not-be-accessed')
    assert invoke(root/'conflict', environment=conflict).returncode != 0
    # Reproduce the original failure: archive signed by one key, app embeds A.
    info['SUPublicEDKey'] = 'o388Mk7QoQjHQ7PBDGrTQ13HkqvO1nyzkfcnmfVumUQ='
    plist.write_bytes(plistlib.dumps(info))
    wrong = root / 'wrong'
    result = invoke(wrong)
    assert result.returncode != 0 and not result.stdout.strip()
    assert not (wrong/'QuickMotion-1.0.4.zip').exists()
    key.write_text('invalid-test-input')
    result = invoke(root/'malformed')
    assert result.returncode != 0 and 'invalid-test-input' not in result.stdout+result.stderr
    print('PASS: matching key, build-number/length metadata, overwrite refusal, version mismatch, conflicting key selection, wrong-key rejection, private-error suppression.')
