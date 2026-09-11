param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CargoArguments)
$ErrorActionPreference = 'Stop'
$isolatedCargo = Join-Path $env:USERPROFILE '.codex\toolchains\gixbee-cargo'
$isolatedRustup = Join-Path $env:USERPROFILE '.codex\toolchains\gixbee-rustup'
if (Test-Path -LiteralPath (Join-Path $isolatedCargo 'bin\cargo.exe')) {
  $env:CARGO_HOME = $isolatedCargo
  $env:RUSTUP_HOME = $isolatedRustup
  $env:PATH = (Join-Path $isolatedCargo 'bin') + ';' + $env:PATH
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$devkitBin = Join-Path $env:USERPROFILE '.codex\toolchains\w64devkit\bin'
$cargoToolchain = @()
if (Test-Path -LiteralPath (Join-Path $devkitBin 'gcc.exe')) {
  $env:PATH = $devkitBin + ';' + $env:PATH
  $cargoToolchain = @('+stable-x86_64-pc-windows-gnu')
} elseif (Test-Path -LiteralPath $vswhere) {
  $vsRoot = & $vswhere -latest -products '*' -property installationPath
  if ($vsRoot) {
    $vcvars = Join-Path $vsRoot 'VC\Auxiliary\Build\vcvars64.bat'
    if (Test-Path -LiteralPath $vcvars) {
      $environmentScript = Join-Path ([IO.Path]::GetTempPath()) ('gixbee-vcvars-' + [guid]::NewGuid() + '.cmd')
      try {
        [IO.File]::WriteAllLines($environmentScript, @('@call "' + $vcvars + '" >nul', '@if errorlevel 1 exit /b 1', '@set'))
        $compilerEnvironment = & cmd.exe /d /c $environmentScript
        if ($LASTEXITCODE -ne 0) { throw 'Visual Studio compiler environment could not be initialized.' }
      } finally { Remove-Item -LiteralPath $environmentScript -ErrorAction SilentlyContinue }
      foreach ($entry in $compilerEnvironment) {
        if ($entry -match '^(PATH|LIB|LIBPATH|INCLUDE|VCINSTALLDIR|VCToolsInstallDir|WindowsSdkDir|WindowsSDKVersion|UniversalCRTSdkDir|UCRTVersion)=(.*)$') {
          [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
      }
    }
  }
}
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  & cargo @cargoToolchain @CargoArguments
  exit $LASTEXITCODE
} finally { Pop-Location }
