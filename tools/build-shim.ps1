# build-shim.ps1 - build and test the native shim.
# 1. Builds and RUNS the host-side protocol unit tests (a failure aborts).
# 2. Builds build\vw_speech.dll (x64) and the host smoke driver.
# 3. Copies vendored prism.dll next to the shim.
# Zero-warning policy: -Wall -Wextra -Werror on everything.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$clang = 'C:\Program Files\LLVM\bin\clang.exe'
$flags = @('-std=c17', '-O2', '-Wall', '-Wextra', '-Werror', '-D_CRT_SECURE_NO_WARNINGS')

New-Item -ItemType Directory -Force -Path "$repo\build" | Out-Null

Write-Host 'build-shim: protocol unit tests...'
& $clang @flags -o "$repo\build\test_protocol.exe" `
    "$repo\src\shim\tests\test_protocol.c" "$repo\src\shim\vw_protocol.c"
if ($LASTEXITCODE -ne 0) { throw 'test build failed' }
& "$repo\build\test_protocol.exe"
if ($LASTEXITCODE -ne 0) { throw 'protocol unit tests FAILED' }

Write-Host 'build-shim: vw_speech.dll...'
& $clang @flags -shared -o "$repo\build\vw_speech.dll" `
    "$repo\src\shim\vw_speech.c" "$repo\src\shim\vw_protocol.c" `
    -lws2_32 -lole32 -luser32
if ($LASTEXITCODE -ne 0) { throw 'shim build failed' }

Write-Host 'build-shim: host smoke driver...'
& $clang @flags -o "$repo\build\host_smoke.exe" "$repo\src\shim\tests\host_smoke.c"
if ($LASTEXITCODE -ne 0) { throw 'smoke driver build failed' }

Copy-Item "$repo\vendor\prism\prism.dll" "$repo\build\prism.dll" -Force
Write-Host 'build-shim: OK'
