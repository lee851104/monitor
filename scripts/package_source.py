"""Export only this project's public source, including the hidden CI folder."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

DIRECTORIES = {'.github', 'App', 'Shared', 'Widget', 'NativeTests', 'tests', 'scripts', 'docs'}
FILES = {'README.md', 'LICENSE', 'package.json', 'project.yml', '.gitignore'}
EXCLUDED_PARTS = {'__pycache__', '.git', 'node_modules', 'build', 'dist'}
EXCLUDED_SUFFIXES = {'.pyc', '.p12', '.pem', '.key', '.mobileprovision', '.cer', '.ipa', '.zip', '.log'}


def package_source(root, output):
    root, output = Path(root).resolve(), Path(output).resolve()
    entries = []
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if path.is_symlink() or not path.is_file():
            continue
        if relative.parts[0] not in DIRECTORIES and relative.as_posix() not in FILES:
            continue
        if any(part in EXCLUDED_PARTS or part.startswith('.env') for part in relative.parts):
            continue
        if path.suffix.lower() in EXCLUDED_SUFFIXES or path.name == '.DS_Store':
            continue
        entries.append((path, relative))
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path, relative in entries:
            archive.write(path, 'TokenBar-iOS/' + relative.as_posix())
    manifest = {'file_count': len(entries), 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                'files': [relative.as_posix() for _, relative in entries]}
    output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    print(package_source(args.root, args.output or args.root / 'dist' / 'TokenBar-iOS-source.zip'))
