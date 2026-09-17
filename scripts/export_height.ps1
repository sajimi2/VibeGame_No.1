param(
    [string]$GodotPath = $env:GODOT_BIN,
    [switch]$Sandbox,
    [switch]$Battlefield
)
# 默认导出战场，同时保留旧启动器使用的 -Battlefield 参数。
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
    # 导出暂存工程移除编辑器插件的自动加载项与配置。
    $config = [regex]::Replace($config, '(?ms)^\[autoload\].*?(?=^\[)', '')
    $config = [regex]::Replace($config, '(?ms)^\[editor_plugins\].*?(?=^\[)', '')
    # 保留导出包原有项目身份，让战场和试验场继续共用已有存档目录。
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
    # 仅清理本次调用创建的 GUID 暂存目录，先校验路径归属及名称。
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStage) -match '^OutpostRPG-export-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
