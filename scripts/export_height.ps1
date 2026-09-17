param([string]$GodotPath = 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe', [switch]$Battlefield)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
# Isolated export project keeps the production main scene and save identity unchanged.
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('OutpostRPG-Height-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $stagingRoot 'scripts/tactical'), (Join-Path $stagingRoot 'scenes') | Out-Null
Copy-Item -Path (Join-Path $projectRoot 'scripts/tactical/*.gd') -Destination (Join-Path $stagingRoot 'scripts/tactical')
# Shared inventory contracts and only the two weapon definitions used here.
$sharedFiles = @('scripts/contracts/inventory_port.gd','scripts/contracts/item_instance.gd','scripts/items/actor_inventory.gd','scripts/items/item_definition.gd','scripts/items/item_catalog.gd','scripts/combat/weapon_profile.gd','scripts/combat/attack_spec.gd','data/items/hunting_knife.tres','data/items/great_cleaver.tres','data/weapons/knife.tres','data/weapons/cleaver.tres','data/attack_knife_light.tres','data/attack_knife_heavy.tres','data/attack_cleaver_light.tres','data/attack_cleaver_heavy.tres')
foreach ($relative in $sharedFiles) {
    $destination = Join-Path $stagingRoot $relative
    New-Item -ItemType Directory -Force (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot $relative) -Destination $destination
}
$scenePath = if ($Battlefield) { 'scenes/battlefield.tscn' } else { 'scenes/tactical_height.tscn' }
$binaryName = if ($Battlefield) { 'OutpostRPG_Battlefield' } else { 'OutpostRPG_HeightLab' }
Copy-Item -LiteralPath (Join-Path $projectRoot $scenePath) -Destination (Join-Path $stagingRoot 'scenes')
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$config = $config.Replace('config/name="Outpost RPG"', 'config/name="Outpost RPG Height Lab"').Replace('res://scenes/level_village.tscn', ('res://' + $scenePath))
# Keep the same project identity so both entries share existing equipment progress.
Set-Content -LiteralPath (Join-Path $stagingRoot 'project.godot') -Value $config -Encoding utf8
Copy-Item -LiteralPath (Join-Path $projectRoot 'export_presets.cfg') -Destination $stagingRoot
$buildPath = Join-Path $projectRoot ('builds/windows/' + $binaryName + '.exe')
& $GodotPath --headless --path $stagingRoot --editor --import *> (Join-Path $projectRoot 'work/height-export-import.log')
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $projectRoot 'work/height-export-import.log') -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)) { throw 'Height export import failed; inspect height-export-import.log' }
& $GodotPath --headless --path $stagingRoot --export-release 'Windows Desktop' $buildPath *> (Join-Path $projectRoot 'work/height-export.log')
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $projectRoot 'work/height-export.log') -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)) { throw 'Height export failed; inspect height-export.log' }
Write-Output "Exported: $buildPath"
