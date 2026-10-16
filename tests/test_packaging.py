import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile


def load_script(name):
    path = Path(__file__).resolve().parents[1] / 'scripts' / f'{name}.py'
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def bundle(self):
        app = self.root / 'TokenBar.app'
        extension = app / 'PlugIns' / 'TokenBarLiveActivity.appex'
        extension.mkdir(parents=True)
        for directory, name, bundle_id in [
            (app, 'TokenBar', 'app.personal.tokenbar'),
            (extension, 'TokenBarLiveActivity', 'app.personal.tokenbar.live'),
        ]:
            info = {'CFBundleIdentifier': bundle_id, 'CFBundleExecutable': name,
                    'CFBundleSupportedPlatforms': ['iPhoneOS']}
            (directory / 'Info.plist').write_bytes(plistlib.dumps(info))
            (directory / name).write_bytes(b'\xcf\xfa\xed\xfe' + b'fixture')
        (app / 'quota-core.js').write_text('/* public program resource */', encoding='utf-8')
        return app

    def test_ipa_contains_executables_extension_and_parser_under_payload(self):
        module = load_script('package_ipa')
        output = self.root / 'TokenBar.ipa'
        module.package_ipa(self.bundle(), output)
        with zipfile.ZipFile(output) as archive:
            self.assertIn('Payload/TokenBar.app/TokenBar', archive.namelist())
            self.assertIn('Payload/TokenBar.app/PlugIns/TokenBarLiveActivity.appex/TokenBarLiveActivity', archive.namelist())
            self.assertIn('Payload/TokenBar.app/quota-core.js', archive.namelist())

    def test_missing_extension_cannot_create_misleading_installable_artifact(self):
        app = self.bundle()
        (app / 'PlugIns/TokenBarLiveActivity.appex/TokenBarLiveActivity').unlink()
        with self.assertRaises(ValueError):
            load_script('package_ipa').package_ipa(app, self.root / 'bad.ipa')
        self.assertFalse((self.root / 'bad.ipa').exists())

    def test_simulator_bundle_is_rejected(self):
        app = self.bundle()
        path = app / 'Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError):
            load_script('package_ipa').package_ipa(app, self.root / 'bad.ipa')

    def test_missing_parser_is_rejected(self):
        app = self.bundle()
        (app / 'quota-core.js').unlink()
        with self.assertRaises(ValueError):
            load_script('package_ipa').package_ipa(app, self.root / 'bad.ipa')

    def test_signing_profile_is_not_distributed_as_unsigned(self):
        app = self.bundle()
        (app / 'embedded.mobileprovision').write_text('PRIVATE', encoding='utf-8')
        with self.assertRaises(ValueError):
            load_script('package_ipa').package_ipa(app, self.root / 'bad.ipa')

    def test_source_zip_has_hidden_workflow_but_no_secrets_builds_or_git(self):
        for name in ['.github/workflows/build-ios.yml', 'App/A.swift', 'README.md',
                     '.gitignore', 'App/.env', 'App/key.p12', 'build/private.txt',
                     '.git/config', 'dist/old.zip', 'App/__pycache__/private.pyc']:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name, encoding='utf-8')
        output = self.root / 'dist/source.zip'
        load_script('package_source').package_source(self.root, output)
        with zipfile.ZipFile(output) as archive:
            names = archive.namelist()
            self.assertIn('TokenBar-iOS/.github/workflows/build-ios.yml', names)
            self.assertIn('TokenBar-iOS/App/A.swift', names)
            self.assertIn('TokenBar-iOS/.gitignore', names)
            self.assertEqual(len(names), 4)

    def test_source_manifest_matches_all_archive_bytes(self):
        import hashlib
        (self.root / 'README.md').write_text('繁體中文', encoding='utf-8')
        output = self.root / 'source.zip'
        load_script('package_source').package_source(self.root, output)
        manifest = json.loads(output.with_suffix('.manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest['sha256'], hashlib.sha256(output.read_bytes()).hexdigest())
        self.assertEqual(manifest['file_count'], 1)


if __name__ == '__main__':
    unittest.main()
