param(
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateSet('smoke','core','art','all')][string]$Suite = 'core',
    [switch]$Rendered
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) { $GodotPath = 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Set -GodotPath or GODOT_BIN to Godot 4.7.2.' }
$logRoot = Join-Path $projectRoot 'work/checks'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
function Invoke-GodotCheck([string]$Name, [string[]]$GodotArgs) {
    $stdout = Join-Path $logRoot ($Name + '.log')
    $stderr = Join-Path $logRoot ($Name + '.err.log')
    $arguments = @('--path', ('"' + $projectRoot + '"')) + $GodotArgs
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(300000)) { $process.Kill(); throw "Timed out: $Name (only this test process was stopped)." }
    $process.WaitForExit()
    $output = @(Get-Content -LiteralPath $stdout) + @(Get-Content -LiteralPath $stderr)
    # 少数已有 SceneTree 测试退出时会报告资源清理；仍须检出所有脚本与运行错误。
    $errors = $output | Where-Object { $_ -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|^FAIL ' -and $_ -notmatch 'Resources still in use at exit' }
    if ($process.ExitCode -ne 0 -or $errors) { $output | Write-Output; throw "Failed: $Name (exit $($process.ExitCode))" }
    $summary = $output | Where-Object { $_ -match '\d+ (checks|traces), \d+ failures' }
    Write-Output ("PASS $Name " + ($summary -join ' '))
}
Invoke-GodotCheck 'import' @('--headless','--editor','--import')
# 显式保留数组类型，避免单个参数与后续数组相加时变成一个字符串。
[string[]]$displayArgs = if ($Rendered) { @() } else { @('--headless') }
Invoke-GodotCheck 'startup' ($displayArgs + @('--script','res://tests/startup_smoke.gd'))
if ($Suite -eq 'smoke') { return }
$tests = @('editable_scene','woodpath_region','woodpath_expedition','baked_player','skeleton_pipeline','pixel_weapon','weapon_choreography','courtyard_combat','courtyard_camera','terrace_ground','rolling_meadow','atlas_pipeline','arrow_attachment','locomotion_art','rock_collision','guard_reaction','attack_motion','melee_aoe','creature_encounter','environment_art','occlusion_presentation','environment_resolution','environment_motion','battlefield','guard_encounter','mission','short_level','camp_loop','space_combat','combat_polish')
$tests += @('wall_occlusion','near_wall_reveal','occlusion_support','selective_wall')
$artTests = @('editable_scene','art_unity','courtyard_camera','terrace_ground','painted_cottage','painted_cottage_motion','painted_courtyard','painted_courtyard_motion','courtyard_presentation','courtyard_shadow_style','meadow_readability','environment_art','occlusion_presentation','environment_resolution')
if ($Suite -eq 'art') { $tests = $artTests }
if ($Suite -eq 'all') { $tests += @('art_unity','height_lab','height_edge','art_route','outpost_sample','letter_interaction','feedback_edges','tower_feedback','waystation_blockout','waystation_combat','painted_cottage','painted_cottage_motion','painted_courtyard','painted_courtyard_motion','courtyard_presentation','courtyard_shadow_style','meadow_readability') }
foreach ($test in $tests) {
    # 绕石压力测试含数万物理帧，用固定 60Hz 加速离线模拟；画面由 locomotion_art 单独验证。
    [string[]]$testDisplay = if ($test -eq 'rock_collision') { @('--headless','--fixed-fps','60') } else { $displayArgs }
    Invoke-GodotCheck $test ($testDisplay + @('--script',"res://tests/tactical/${test}_test.gd"))
}
Write-Output 'Player saves were isolated by tactical/testing. Rendered visual review and subjective play feel are separate.'
