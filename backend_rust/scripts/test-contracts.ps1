param([Parameter(Mandatory = $true)][string]$DatabaseUrl)
$ErrorActionPreference = 'Stop'
$env:GIXBEE_TEST_DATABASE_URL = $DatabaseUrl
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
  # The setup program refuses non-local databases and names outside gixbee_contract_*.
  node backend_rust/tests/setup-database.cjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & (Join-Path $PSScriptRoot 'cargo-local.ps1') -CargoArguments @('test', '--bin', 'gixbee-backend', '--', '--include-ignored')
  exit $LASTEXITCODE
} finally { Pop-Location }
