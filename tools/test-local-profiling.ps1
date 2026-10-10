param(
    [string]$PhpExecutable = 'php',
    [string]$GodotExecutable = 'godot',
    [string]$Configuration = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Configuration -eq '') {
    $Configuration = Join-Path $projectRoot 'config/development/profiling.json'
}
$configPath = (Resolve-Path -LiteralPath $Configuration).Path
$preset = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($preset.development_only -ne $true -or $preset.receiver.address -notmatch '^127\.0\.0\.1:([0-9]{1,5})$') {
    throw 'The smoke runner requires a development-only loopback receiver.'
}
$port = [int]$Matches[1]
$phpCommand = (Get-Command $PhpExecutable -CommandType Application | Select-Object -First 1).Source
$godotCommand = (Get-Command $GodotExecutable -CommandType Application | Select-Object -First 1).Source
$receiverScript = Join-Path $projectRoot 'tools/run-profiling-receiver.php'
if ($receiverScript.Contains('"') -or $configPath.Contains('"')) {
    throw 'Quoted filenames are not supported by this development launcher.'
}
$outputDirectory = Join-Path $projectRoot 'var/profiling-tests'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$receiver = $null
try {
    $probe = [System.Net.Sockets.TcpClient]::new()
    try {
        $probe.Connect('127.0.0.1', $port)
        throw 'The profiling port is already in use. Stop the previous receiver first.'
    } catch [System.Net.Sockets.SocketException] {
        # Expected when no previous receiver is listening.
    } finally {
        $probe.Dispose()
    }
    $launch = @{
        FilePath = $phpCommand
        ArgumentList = @(('"' + $receiverScript + '"'), ('"' + $configPath + '"'))
        WorkingDirectory = $projectRoot
        RedirectStandardOutput = Join-Path $outputDirectory 'receiver.stdout.log'
        RedirectStandardError = Join-Path $outputDirectory 'receiver.stderr.log'
        PassThru = $true
    }
    if ($IsWindows) {
        $launch.WindowStyle = 'Hidden'
    }
    $receiver = Start-Process @launch
    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and -not $receiver.HasExited) {
        $probe = [System.Net.Sockets.TcpClient]::new()
        try {
            $probe.Connect('127.0.0.1', $port)
            $ready = $true
            break
        } catch [System.Net.Sockets.SocketException] {
            Start-Sleep -Milliseconds 100
        } finally {
            $probe.Dispose()
        }
    }
    if (-not $ready) {
        throw 'Local receiver startup failed. See var/profiling-tests/receiver.stderr.log.'
    }
    $fixture = Get-Content -LiteralPath (Join-Path $projectRoot 'tests/fixtures/profiling/empty-capture.v1.json') -Raw | ConvertFrom-Json
    $fixture.world_id = $preset.host.world_id
    $fixture.region_id = $preset.host.region_id
    $body = $fixture | ConvertTo-Json -Depth 16 -Compress
    $authorization = @{ Authorization = 'Bearer ' + $preset.authentication.bearer_token }
    $stored = Invoke-WebRequest -Uri $preset.uploader.endpoint -Method Post -Headers $authorization -ContentType 'application/json' -Body $body -SkipHttpErrorCheck -TimeoutSec 20
    if ([int]$stored.StatusCode -ne 200) { throw 'Initial fixture capture failed.' }
    $receipt = $stored.Content | ConvertFrom-Json
    $repeat = Invoke-WebRequest -Uri $preset.uploader.endpoint -Method Post -Headers $authorization -ContentType 'application/json' -Body $body -SkipHttpErrorCheck -TimeoutSec 20
    if ([int]$repeat.StatusCode -ne 200 -or ($repeat.Content | ConvertFrom-Json).sequence -ne $receipt.sequence) {
        throw 'Identical capture retry did not return its retained receipt.'
    }
    Write-Output 'PASS: identical capture retry retains its receipt'
    $fixture.world_id = 'unassigned-test-world'
    if ($fixture.world_id -eq $preset.host.world_id) { $fixture.world_id = 'another-unassigned-test-world' }
    $cases = @(
        @{ Name = 'invalid credential'; Expected = 401; Headers = @{ Authorization = 'Bearer invalid-fixture-token' }; Body = $body },
        @{ Name = 'malformed capture'; Expected = 422; Headers = $authorization; Body = '{}' },
        @{ Name = 'wrong host scope'; Expected = 422; Headers = $authorization; Body = ($fixture | ConvertTo-Json -Depth 16 -Compress) },
        @{ Name = 'oversized capture'; Expected = 413; Headers = $authorization; Body = ('x' * ([int]$preset.receiver.maximum_bytes + 1)) }
    )
    foreach ($case in $cases) {
        $response = Invoke-WebRequest -Uri $preset.uploader.endpoint -Method Post -Headers $case.Headers -ContentType 'application/json' -Body $case.Body -SkipHttpErrorCheck -TimeoutSec 20
        if ([int]$response.StatusCode -ne $case.Expected) { throw ('Unexpected rejection status for ' + $case.Name) }
        Write-Output ('PASS: ' + $case.Name + ' => ' + $response.StatusCode)
    }
    & $godotCommand --headless --path $projectRoot --script res://tests/godot/local_profiling_upload_test.gd -- "--profiling-config=$configPath"
    if ($LASTEXITCODE -ne 0) {
        throw 'Godot profiling upload smoke test failed.'
    }
    $stale = Invoke-WebRequest -Uri $preset.uploader.endpoint -Method Post -Headers $authorization -ContentType 'application/json' -Body $body -SkipHttpErrorCheck -TimeoutSec 20
    if ([int]$stale.StatusCode -ne 422) { throw 'An older fixture capture overwrote newer Godot telemetry.' }
    Write-Output 'PASS: delayed capture rejects after a newer Godot upload'
} finally {
    if ($null -ne $receiver -and -not $receiver.HasExited) {
        Stop-Process -Id $receiver.Id -Force
    }
}
