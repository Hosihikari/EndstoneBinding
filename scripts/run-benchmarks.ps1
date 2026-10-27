param(
    [Parameter(Mandatory = $true)]
    [string]$ServerRoot,
    [Parameter(Mandatory = $true)]
    [string]$EndstoneRoot,
    [string]$Python = "python",
    [string]$GeneratorRoot = "",
    [string]$AbiRoot = "",
    [string]$LlvmRoot = "$env:LOCALAPPDATA\Temp\hosihikari-llvm\clang+llvm-23.1.3-x86_64-pc-windows-msvc",
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ServerRoot = (Resolve-Path $ServerRoot).Path
$EndstoneRoot = (Resolve-Path $EndstoneRoot).Path
if ([string]::IsNullOrWhiteSpace($GeneratorRoot)) {
    $GeneratorRoot = (Resolve-Path (Join-Path $RepoRoot "..\Binding.Generator")).Path
} else {
    $GeneratorRoot = (Resolve-Path $GeneratorRoot).Path
}
if ([string]::IsNullOrWhiteSpace($AbiRoot)) {
    $AbiRoot = (Resolve-Path (Join-Path (Split-Path $RepoRoot -Parent) "Binding.Abi")).Path
} else {
    $AbiRoot = (Resolve-Path $AbiRoot).Path
}

dotnet build (Join-Path $RepoRoot "Hosihikari.Bindings.Endstone.slnx") -c Release --nologo -v:q
& (Join-Path $RepoRoot "native\BindingShim\build.ps1") -EndstoneRoot $EndstoneRoot -GeneratorRoot $GeneratorRoot

$BenchmarkDirectory = Join-Path $RepoRoot "artifacts\benchmarks"
$PluginDll = Join-Path $BenchmarkDirectory "shim_benchmarks.dll"
& (Join-Path $PSScriptRoot "..\tests\benchmarks\build.ps1") `
    -EndstoneRoot $EndstoneRoot `
    -OutputDll $PluginDll `
    -LlvmRoot $LlvmRoot `
    -AbiProjectPath (Join-Path $AbiRoot "src\Hosihikari.Bindings.Abi\Hosihikari.Bindings.Abi.csproj")

$PluginsTarget = Join-Path $ServerRoot "plugins"
$PayloadTarget = Join-Path $PluginsTarget "hosihikari-benchmarks"
New-Item -ItemType Directory -Force -Path $PluginsTarget | Out-Null
if (Test-Path $PayloadTarget) {
    Remove-Item $PayloadTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $PayloadTarget | Out-Null
Copy-Item $PluginDll (Join-Path $PluginsTarget "shim_benchmarks.dll") -Force
Copy-Item (Join-Path $BenchmarkDirectory "hosihikari-benchmarks\*") $PayloadTarget -Recurse -Force

$LocalPlugins = Join-Path $PluginsTarget ".local"
if (Test-Path $LocalPlugins) {
    Get-ChildItem $LocalPlugins -Filter "shim_benchmarks-*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem $LocalPlugins -Filter "shim_smoke-*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force
}
Remove-Item (Join-Path $PluginsTarget "shim_smoke.dll") -Force -ErrorAction SilentlyContinue

$ShimDll = Join-Path $RepoRoot "artifacts\native\Hosihikari.Bindings.Endstone.Shim.dll"
$PayloadShim = Join-Path $PayloadTarget "Hosihikari.Bindings.Endstone.Shim.dll"
Copy-Item $ShimDll $PayloadShim -Force

$ResultDirectory = Join-Path $ServerRoot "data\hosihikari\shim-benchmarks"
New-Item -ItemType Directory -Force -Path $ResultDirectory | Out-Null
$ResultPath = Join-Path $ResultDirectory "benchmarks.txt"
Remove-Item $ResultPath -Force -ErrorAction SilentlyContinue

$env:HS_BENCH_RESULT = $ResultPath
$env:HS_BENCH_SHIM = $PayloadShim

$Process = Start-Process `
    -FilePath $Python `
    -ArgumentList @("-m", "endstone", "-s", $ServerRoot, "-y", "--no-interactive") `
    -WorkingDirectory $ServerRoot `
    -PassThru `
    -NoNewWindow

$Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ([DateTime]::UtcNow -lt $Deadline) {
    if (Test-Path $ResultPath) {
        break
    }

    if ($Process.HasExited) {
        break
    }

    Start-Sleep -Seconds 1
}

if (-not $Process.HasExited) {
    $Process.Kill()
    $Process.WaitForExit(10000) | Out-Null
}

if (-not (Test-Path $ResultPath)) {
    throw "Endstone benchmarks did not produce $ResultPath within $TimeoutSeconds seconds."
}

$Result = Get-Content $ResultPath -Raw
Write-Output $Result.TrimEnd()
if ($Result -notmatch '(?m)^result=OK\s*$') {
    throw "Endstone benchmarks failed; see $ResultPath."
}

Write-Output "Endstone benchmarks passed."
