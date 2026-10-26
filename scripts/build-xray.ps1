param(
  [string]$Sdk = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony',
  [string]$GoRoot = '',
  [string]$GoProxy = 'https://goproxy.cn,direct'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$GoRoot) { $GoRoot = Join-Path $root '.native-cache/ohos-go-19667c7abfc332f848b5bd1f293e4aeb0e9991a9' }
if (!(Test-Path "$GoRoot/bin/go.exe")) { throw 'Run scripts/prepare-native.ps1 first.' }
$env:GOROOT = $GoRoot
$env:GOTOOLCHAIN = 'local'
$env:GOENV = 'off'
$env:GOCACHE = "$root/.native-cache/gocache"
$env:GOMODCACHE = "$root/.native-cache/gomod"
$env:GOPROXY = $GoProxy
$env:GOOS = 'openharmony'
$env:GOARCH = 'arm64'
$env:CGO_ENABLED = '1'
$sdkLink = "$root/.native-cache/ohos-sdk"
if (!(Test-Path $sdkLink)) { New-Item -ItemType Junction -Path $sdkLink -Target $Sdk | Out-Null }
$env:CC = "$sdkLink/native/llvm/bin/clang.exe --target=aarch64-linux-ohos --sysroot=$sdkLink/native/sysroot -D__MUSL__"
$env:CGO_CFLAGS = '-O2 -ftls-model=global-dynamic'
$env:CGO_LDFLAGS = '-Wl,-z,max-page-size=16384'
$output = "$root/entry/libs/arm64-v8a"
New-Item $output -ItemType Directory -Force | Out-Null
Push-Location "$root/native/xray"
try {
  & "$GoRoot/bin/go.exe" build -trimpath -buildmode=c-shared -ldflags='-s -w -extldflags=-Wl,-soname,libharmony_xray.so' -o "$output/libharmony_xray.so" .
  if ($LASTEXITCODE) { throw 'Xray cross-compilation failed.' }
  $tls = & "$Sdk/native/llvm/bin/llvm-readelf.exe" -r "$output/libharmony_xray.so"
  if (!($tls -match 'R_AARCH64_TLSDESC')) { throw 'Missing TLSDESC; this Go toolchain is incompatible with dynamic loading on HarmonyOS.' }
  & node "$PSScriptRoot/collect-native-licenses.mjs"
  if ($LASTEXITCODE) { throw 'Native license collection failed.' }
  Write-Host 'Built HarmonyOS arm64 Xray with TLSDESC.'
} finally { Pop-Location }
