"""Package a built, unsigned device app. Never turn simulator builds into IPAs."""
import argparse
from pathlib import Path
import plistlib
import zipfile


def validate_bundle(bundle, expected_identifier):
    try:
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValueError(f'Missing or invalid bundle metadata: {bundle.name}') from error
    if info.get('CFBundleIdentifier') != expected_identifier:
        raise ValueError(f'Unexpected bundle identifier: {bundle.name}')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('A physical-device iPhoneOS build is required, not a simulator build')
    executable_name = info.get('CFBundleExecutable', '')
    if not executable_name or Path(executable_name).name != executable_name:
        raise ValueError('Missing or unsafe executable name')
    executable = bundle / executable_name
    if not executable.is_file() or executable.read_bytes()[:4] not in (
        b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf',
    ):
        raise ValueError(f'Missing Mach-O executable: {bundle.name}')


def package_ipa(app, output):
    app, output = Path(app).resolve(), Path(output).resolve()
    if app.name != 'TokenBar.app':
        raise ValueError('Expected TokenBar.app')
    if app in output.parents:
        raise ValueError('Output must be outside the app bundle')
    validate_bundle(app, 'app.personal.tokenbar')
    validate_bundle(app / 'PlugIns' / 'TokenBarLiveActivity.appex', 'app.personal.tokenbar.live')
    if not (app / 'quota-core.js').is_file():
        raise ValueError('quota-core.js is missing from the app resources')
    entries = sorted(app.rglob('*'))
    if any(path.is_symlink() for path in entries):
        raise ValueError('Unexpected symbolic link in app bundle')
    if any(path.suffix in ('.mobileprovision', '.p12') for path in entries):
        raise ValueError('Unsigned distribution must not contain signing credentials or profiles')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in entries:
            if path.is_file():
                archive.write(path, 'Payload/' + app.name + '/' + path.relative_to(app).as_posix())
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(package_ipa(args.app, args.output))
