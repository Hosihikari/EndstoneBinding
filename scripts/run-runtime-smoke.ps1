param(
    [Parameter(Mandatory = $true)]
    [string]$ServerRoot,
    [Parameter(Mandatory = $true)]
    [string]$EndstoneRoot,
    [string]$Python = "python",
    [string]$GeneratorRoot = "",
    [int]$TimeoutSeconds = 180
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

dotnet build (Join-Path $RepoRoot "Hosihikari.Bindings.Endstone.slnx") -c Release --nologo -v:q
& (Join-Path $RepoRoot "native\BindingShim\build.ps1") -EndstoneRoot $EndstoneRoot -GeneratorRoot $GeneratorRoot

$PluginDirectory = Join-Path $RepoRoot "artifacts\runtime-smoke"
$PluginDll = Join-Path $PluginDirectory "shim_smoke.dll"
& (Join-Path $PSScriptRoot "..\tests\runtime-smoke\build.ps1") -EndstoneRoot $EndstoneRoot -OutputDll $PluginDll

$ShimDll = Join-Path $RepoRoot "artifacts\native\Hosihikari.Bindings.Endstone.Shim.dll"
$PluginsTarget = Join-Path $ServerRoot "plugins"
New-Item -ItemType Directory -Force -Path $PluginsTarget | Out-Null
Copy-Item $PluginDll (Join-Path $PluginsTarget "shim_smoke.dll") -Force
Copy-Item $ShimDll (Join-Path $PluginsTarget "Hosihikari.Bindings.Endstone.Shim.dll") -Force

$LocalPlugins = Join-Path $PluginsTarget ".local"
if (Test-Path $LocalPlugins) {
    Get-ChildItem $LocalPlugins -Filter "shim_smoke-*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force
}

$ResultPath = Join-Path $ServerRoot "shim-smoke-result.txt"
Remove-Item $ResultPath -Force -ErrorAction SilentlyContinue

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
    throw "Endstone runtime smoke did not produce $ResultPath within $TimeoutSeconds seconds."
}

$Result = Get-Content $ResultPath -Raw
Write-Output $Result.TrimEnd()
if ($Result -notmatch '(?m)^result=OK\s*$') {
    throw "Endstone runtime smoke failed; see $ResultPath."
}

Write-Output "Endstone runtime smoke passed."
