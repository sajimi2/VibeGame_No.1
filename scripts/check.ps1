param(
    [string]$GodotPath = 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable missing: $GodotPath" }
$logRoot = Join-Path $projectRoot 'work'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$stages = @(
    @{ Name = 'import'; Args = @('--headless', '--path', $projectRoot, '--editor', '--import', '--log-file', (Join-Path $logRoot 'import.log')) },
    @{ Name = 'startup'; Args = @('--headless', '--path', $projectRoot, '--quit-after', '3', '--log-file', (Join-Path $logRoot 'startup.log')) }
)
foreach ($stage in $stages) {
    $stageArgs = $stage.Args
    $output = & $GodotPath @stageArgs 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $logRoot ($stage.Name + '-console.log')) -Encoding utf8
    $errors = $output | Select-String -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:'
    if ($code -ne 0 -or $errors) { $output | Write-Output; throw "Stage $($stage.Name) failed (exit $code)." }
    Write-Output "$($stage.Name): PASS (exit $code)"
}
$contractRoot = Join-Path $PSScriptRoot 'contracts'
foreach ($contractFile in (Get-ChildItem -LiteralPath $contractRoot -Filter '*.gd')) {
    $output = & $GodotPath --headless --path $projectRoot --script $contractFile.FullName --check-only 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $logRoot ($contractFile.BaseName + '-parse.log')) -Encoding utf8
    if ($code -ne 0 -or ($output | Select-String -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:')) {
        $output | Write-Output
        throw "Contract $($contractFile.Name) failed (exit $code)."
    }
    Write-Output "$($contractFile.Name): PASS (exit $code)"
}
Write-Output 'Only import/parse/headless startup checked. Gameplay and rendered visuals require separate validation.'
