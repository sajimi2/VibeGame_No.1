param(
    [string]$GodotPath = $env:GODOT_BIN,
    [switch]$Sandbox,
    [switch]$Battlefield
)
# -Battlefield remains accepted for the previous launcher; battlefield is now the default.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) { $GodotPath = 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('OutpostRPG-export-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    foreach ($directory in @('scripts','data','scenes')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $stage -Recurse
    }
    $config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
    # Editor tooling is not a game dependency; omit the plugin autoload/config from the export staging project.
    $config = [regex]::Replace($config, '(?ms)^\[autoload\].*?(?=^\[)', '')
    $config = [regex]::Replace($config, '(?ms)^\[editor_plugins\].*?(?=^\[)', '')
    # Preserve the existing exported game's save identity, shared by battlefield and sandbox.
    $config = $config.Replace('config/name="Outpost RPG"', 'config/name="Outpost RPG Height Lab"')
    if ($Sandbox) { $config = $config.Replace('res://scenes/battlefield.tscn','res://scenes/tactical_height.tscn') }
    Set-Content -LiteralPath (Join-Path $stage 'project.godot') -Value $config -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $projectRoot 'export_presets.cfg') -Destination $stage
    $binaryName = if ($Sandbox) { 'OutpostRPG_HeightLab' } else { 'OutpostRPG_Battlefield' }
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'work'), (Join-Path $projectRoot 'builds/windows') -Force | Out-Null
    foreach ($phase in @('import','export')) {
        $phaseArgs = if ($phase -eq 'import') { @('--headless','--path',$stage,'--editor','--import') } else { @('--headless','--path',$stage,'--export-release','Windows Desktop',(Join-Path $projectRoot "builds/windows/$binaryName.exe")) }
        $log = Join-Path $projectRoot "work/$binaryName-$phase.log"
        & $GodotPath @phaseArgs *> $log
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)) { throw "Export $phase failed; see $log" }
    }
    Write-Output "Exported: builds/windows/$binaryName.exe (keep its matching .pck)"
} finally {
    # Only remove this invocation's GUID staging directory, never the project or all temp files.
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStage) -match '^OutpostRPG-export-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
