param([switch]$SkipXrayBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cache = Join-Path $root '.native-cache'
New-Item $cache -ItemType Directory -Force | Out-Null
function Get-VerifiedArchive([string]$Url, [string]$Path, [string]$Hash) {
  if (!(Test-Path $Path)) { Invoke-WebRequest -Uri $Url -OutFile $Path }
  if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Hash) {
    throw "Archive checksum mismatch: $Path"
  }
}
$bootstrapZip = "$cache/go1.26.5.windows-amd64.zip"
Get-VerifiedArchive 'https://go.dev/dl/go1.26.5.windows-amd64.zip' $bootstrapZip '97e6b2a833b6d89f9ff17d25419ac0a7e3b482a044e9ab18cdef834bd834fd38'
if (!(Test-Path "$cache/go/bin/go.exe")) { Expand-Archive -LiteralPath $bootstrapZip -DestinationPath $cache }
$revision = '19667c7abfc332f848b5bd1f293e4aeb0e9991a9'
$source = "$cache/ohos-go-$revision"
$archive = "$cache/ohos-go-19667c7.tar.gz"
Get-VerifiedArchive "https://codeload.github.com/star4277/ohos-go/tar.gz/$revision" $archive '0263efd155b3d729cede7e9fbb6eca3d994dd6e0f4b9a597a675a581831ef0f2'
if (!(Test-Path $source)) {
  & tar -xzf $archive -C $cache
  if ($LASTEXITCODE) { throw 'Go source extraction failed.' }
}
if (!(Test-Path "$source/bin/go.exe")) {
  $env:GOROOT_BOOTSTRAP = "$cache/go"
  $env:GOTOOLCHAIN = 'local'
  $env:CGO_ENABLED = '0'
  $env:GOENV = 'off'
  $env:GOCACHE = "$cache/gocache"
  Remove-Item Env:GOROOT, Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
  Push-Location "$source/src"
  try { & cmd /c make.bat; if ($LASTEXITCODE) { throw 'OpenHarmony Go bootstrap failed.' } }
  finally { Pop-Location }
}
# Hev SOCKS5 tunnel is vendored at entry/src/main/cpp/third-party/hev-socks5-tunnel.
Push-Location $root
try {
  if (!$SkipXrayBuild) { & "$PSScriptRoot/build-xray.ps1" }
} finally { Pop-Location }
