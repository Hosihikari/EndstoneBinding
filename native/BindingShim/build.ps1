param(
    [string]$EndstoneRoot = "",
    [string]$GeneratorRoot = "",
    [string]$LlvmRoot = "$env:LOCALAPPDATA\Temp\hosihikari-llvm\clang+llvm-23.1.3-x86_64-pc-windows-msvc",
    [string]$Output = "artifacts/native"
)
if ([string]::IsNullOrWhiteSpace($EndstoneRoot)) {
    $EndstoneRoot = Join-Path $PSScriptRoot "..\..\..\Third\Endstone"
}

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($GeneratorRoot)) {
    $GeneratorRoot = (Resolve-Path (Join-Path $RepoRoot "..\Binding.Generator")).Path
} else {
    $GeneratorRoot = (Resolve-Path $GeneratorRoot).Path
}
$EndstoneRoot = (Resolve-Path $EndstoneRoot).Path
$Output = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $RepoRoot $Output }
New-Item -ItemType Directory -Force -Path $Output | Out-Null

$ShimDirectory = Join-Path $PSScriptRoot "generated\win-x64-server\endstone"
if (-not (Test-Path (Join-Path $ShimDirectory "binding_table.cpp"))) {
    throw "Generated BindingShim sources are missing under $ShimDirectory."
}

& (Join-Path $GeneratorRoot "frontend\build-endstone-shim.ps1") `
    -ShimDirectory $ShimDirectory `
    -OutputDll (Join-Path $Output "Hosihikari.Bindings.Endstone.Shim.dll") `
    -LlvmRoot $LlvmRoot `
    -EndstoneRoot $EndstoneRoot
