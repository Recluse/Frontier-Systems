param(
    [string]$GodotPath = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$VR,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$taskProjectPath = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath. Supply -GodotPath with the executable's full path."
}
$taskLaunchArguments = @('--path', $taskProjectPath)
if ($VR) {
    $taskLaunchArguments += @('--rendering-method', 'mobile', '--rendering-driver', 'vulkan', '--xr-mode', 'on', '--', '--vr')
} else {
    $taskLaunchArguments += @('--xr-mode', 'off')
}
if ($CheckOnly) {
    [pscustomobject]@{ Executable = $GodotPath; Arguments = $taskLaunchArguments; VR = [bool]$VR }
    return
}
& $GodotPath @taskLaunchArguments
exit $LASTEXITCODE
