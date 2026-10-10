param([string]$Godot = "", [string]$Php = "")
$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Php -eq "") { $Php = (Get-Command php -CommandType Application | Select-Object -First 1).Source }
if ($Godot -eq "") { $Godot = (Get-Command godot -CommandType Application | Select-Object -First 1).Source }
$savedEnvironment = @{}
foreach ($name in @("FRONTIER_EVENT_TOKEN", "FRONTIER_EVENT_URL", "FRONTIER_EVENT_ADDRESS", "FRONTIER_EVENT_WORLD", "FRONTIER_EVENT_REGION")) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
$receiver = $null
$gameCheck = $null
$stamp = [Guid]::NewGuid().ToString("N")
$logDir = Join-Path $projectRoot "var/event-logging"
New-Item -ItemType Directory -Force $logDir | Out-Null
$stdout = Join-Path $logDir "$stamp.out.log"
$stderr = Join-Path $logDir "$stamp.err.log"
try {
    $env:FRONTIER_EVENT_TOKEN = [Guid]::NewGuid().ToString("N") + [Guid]::NewGuid().ToString("N")
    $env:FRONTIER_EVENT_URL = "http://127.0.0.1:27843/v1/events"
    $env:FRONTIER_EVENT_ADDRESS = "127.0.0.1:27843"
    $env:FRONTIER_EVENT_WORLD = "development-world"
    $env:FRONTIER_EVENT_REGION = "local-habitat"
    $arguments = @{FilePath=$Php;ArgumentList=@("tools/run-event-receiver.php");WorkingDirectory=$projectRoot;PassThru=$true;RedirectStandardOutput=$stdout;RedirectStandardError=$stderr}
    if ($IsWindows) { $arguments.WindowStyle = "Hidden" }
    $receiver = Start-Process @arguments
    $ready = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        if ($receiver.HasExited) { throw "Event receiver exited before startup." }
        $client = [Net.Sockets.TcpClient]::new()
        try { $client.Connect("127.0.0.1",27843); $ready=$true; break } catch { Start-Sleep -Milliseconds 100 } finally { $client.Dispose() }
    }
    if (-not $ready) { throw "Event receiver did not start." }
    $gameOut = Join-Path $logDir "$stamp.godot.out.log"
    $gameErr = Join-Path $logDir "$stamp.godot.err.log"
    $gameArguments = @{FilePath=$Godot;ArgumentList=@("--headless", "--xr-mode", "off", "--path", ".", "--script", "res://tests/godot/event_logging_integration_test.gd");WorkingDirectory=$projectRoot;PassThru=$true;RedirectStandardOutput=$gameOut;RedirectStandardError=$gameErr}
    if ($IsWindows) { $gameArguments.WindowStyle = "Hidden" }
    $gameCheck = Start-Process @gameArguments
    if (-not $gameCheck.WaitForExit(20000)) { throw "Godot event check exceeded its deadline." }
    Write-Output (Get-Content $gameOut -Raw)
    $errors = Get-Content $gameErr -Raw
    if ($gameCheck.ExitCode -ne 0 -or $errors -match "SCRIPT ERROR|ERROR:") { throw "Godot event logging integration failed: $errors" }
    $text = Get-Content $stdout -Raw
    if (-not $text.Contains("event-integration-public") -or -not $text.Contains("event-integration-staff") -or $text.Contains($env:FRONTIER_EVENT_TOKEN) -or $text.Contains("never-log-this")) { throw "Event output omitted an event or exposed credentials." }
    Write-Output "Event logging integration passed without Discord sends."
} finally {
    if ($null -ne $gameCheck -and -not $gameCheck.HasExited) { Stop-Process -Id $gameCheck.Id }
    if ($null -ne $receiver -and -not $receiver.HasExited) { Stop-Process -Id $receiver.Id }
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
}
