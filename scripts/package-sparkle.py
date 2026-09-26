#!/usr/bin/env python3
"""Package an exported app; emit a feed item only after independent verification."""
import argparse
import base64
import datetime
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def package(args):
    app = Path(args.app).resolve()
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != 'com.lucesumbrarum.quickmotion':
        raise ValueError('Expected a QuickMotion app bundle')
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    key = info['SUPublicEDKey']
    for value in (version, build):
        if not isinstance(value, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', value):
            raise ValueError('Bundle versions must be numeric dotted strings')
    if args.version and args.version != version:
        raise ValueError('Requested version differs from the exported app version')
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError('Invalid embedded Sparkle public key')
    account = os.environ.get('SPARKLE_ACCOUNT')
    key_file = os.environ.get('SPARKLE_KEY_FILE')
    if bool(account) == bool(key_file):
        raise ValueError('Set exactly one of SPARKLE_ACCOUNT or SPARKLE_KEY_FILE explicitly')
    tool_dir = os.environ.get('SPARKLE_BIN')
    if not tool_dir:
        raise ValueError('Set SPARKLE_BIN to the intended Sparkle distribution bin directory')
    signer = Path(tool_dir).resolve() / 'sign_update'
    if not signer.is_file():
        raise ValueError('SPARKLE_BIN does not contain sign_update')
    selection = ['--account', account] if account else ['--ed-key-file', str(Path(key_file).resolve())]
    if key_file and not Path(key_file).is_file():
        raise ValueError('SPARKLE_KEY_FILE must refer to a local key file')

    # Require valid Apple signing and a valid stapled notarization ticket.
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    run(['xcrun', 'stapler', 'validate', str(app)], stdout=subprocess.DEVNULL)
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = f'QuickMotion-{version}.zip'
    destination = output / name
    if destination.exists():
        raise ValueError('Release archive already exists; use a new version or an empty staging directory')
    with tempfile.TemporaryDirectory(prefix='.quickmotion-', dir=output) as temporary:
        temporary = Path(temporary)
        archive = temporary / name
        run(['ditto', '-c', '-k', '--keepParent', str(app), str(archive)])
        # Read metadata from the ZIP itself, so verification binds to shipped bytes.
        import zipfile
        with zipfile.ZipFile(archive) as zipped:
            packed = plistlib.loads(zipped.read(f'{app.name}/Contents/Info.plist'))
        if packed != info:
            raise ValueError('App metadata changed while packaging')
        signed = run([str(signer), *selection, '-p', str(archive)],
                     capture_output=True, text=True)
        signature = signed.stdout.strip()
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError('Signer did not return a valid Ed25519 signature')
        verifier = temporary / 'verify-sparkle'
        run(['xcrun', 'swiftc', str(Path(__file__).with_name('verify-sparkle.swift')),
             '-module-cache-path', str(temporary / 'module-cache'), '-o', str(verifier)])
        run([str(verifier), str(archive), packed['SUPublicEDKey'], signature])
        size = archive.stat().st_size
        # Exclusive publication prevents accidental replacement of an existing release.
        os.link(archive, destination)

    namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    ET.register_namespace('sparkle', namespace)
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = f'Version {version}'
    ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S %z')
    ET.SubElement(item, f'{{{namespace}}}version').text = build
    ET.SubElement(item, f'{{{namespace}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{namespace}}}minimumSystemVersion').text = info.get('LSMinimumSystemVersion', '14.0')
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/Xpycode/QuickMotion/releases/download/v{version}/{name}',
        f'{{{namespace}}}edSignature': signature,
        'length': str(size), 'type': 'application/octet-stream',
    })
    print(ET.tostring(item, encoding='unicode'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app')
    parser.add_argument('version', nargs='?')
    parser.add_argument('--output', default=str(Path(__file__).resolve().parent.parent / 'releases'))
    arguments = parser.parse_args()
    try:
        package(arguments)
    except subprocess.CalledProcessError:
        # Sparkle's malformed-key errors can contain private input. Never echo them.
        parser.exit(1, 'Release validation or signing failed; no appcast item emitted.\n')
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException):
        parser.exit(1, 'Release input invalid. Check bundle metadata, explicit signer settings, version and output path.\n')
