param([string]$GodotPath = 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
# Isolated export project keeps the production main scene and save identity unchanged.
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('OutpostRPG-Height-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $stagingRoot 'scripts/tactical'), (Join-Path $stagingRoot 'scenes') | Out-Null
Copy-Item -Path (Join-Path $projectRoot 'scripts/tactical/*.gd') -Destination (Join-Path $stagingRoot 'scripts/tactical')
Copy-Item -LiteralPath (Join-Path $projectRoot 'scenes/tactical_height.tscn') -Destination (Join-Path $stagingRoot 'scenes')
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$config = $config.Replace('config/name="Outpost RPG"', 'config/name="Outpost RPG Height Lab"').Replace('res://scenes/level_village.tscn', 'res://scenes/tactical_height.tscn')
Set-Content -LiteralPath (Join-Path $stagingRoot 'project.godot') -Value $config -Encoding utf8
Copy-Item -LiteralPath (Join-Path $projectRoot 'export_presets.cfg') -Destination $stagingRoot
$buildPath = Join-Path $projectRoot 'builds/windows/OutpostRPG_HeightLab.exe'
& $GodotPath --headless --path $stagingRoot --editor --import *> (Join-Path $projectRoot 'work/height-export-import.log')
if ($LASTEXITCODE -ne 0) { throw 'Height export import failed' }
& $GodotPath --headless --path $stagingRoot --export-release 'Windows Desktop' $buildPath *> (Join-Path $projectRoot 'work/height-export.log')
if ($LASTEXITCODE -ne 0) { throw 'Height export failed' }
Write-Output "Exported: $buildPath"
