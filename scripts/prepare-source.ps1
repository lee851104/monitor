$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectPath
try {
    & node --test tests/quota.test.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Quota tests failed.' }
    & python -m unittest discover -s tests -p 'test_*.py' -v
    if ($LASTEXITCODE -ne 0) { throw 'Packaging tests failed.' }
    & python scripts/package_source.py
    if ($LASTEXITCODE -ne 0) { throw 'Source packaging failed.' }
    Get-FileHash -LiteralPath 'dist/TokenBar-iOS-source.zip' -Algorithm SHA256
} finally {
    Pop-Location
}
