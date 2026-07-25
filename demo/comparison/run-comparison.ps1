[CmdletBinding()]
param(
    [int]$Events = 12000,
    [int]$WarmupEvents = 1200,
    [int]$IntervalMs = 500,
    [int]$Trials = 3,
    [string]$NephtysSource = 'C:\dev\Nephtys-uic-benchmark',
    [string]$ResultsDir = '',
    [int]$MaxAttemptsPerSlot = 2
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$expectedNephtysCommit = 'c146ee7c397fd415194635b0e872d30f3cc87c0a'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$comparisonDir = $PSScriptRoot
$nodeRedDir = Join-Path $comparisonDir 'nodered'
$composeFile = Join-Path $comparisonDir 'compose.yml'
$tempBin = Join-Path $env:TEMP 'nephtys-comparison-bin'
New-Item -ItemType Directory -Force -Path $tempBin | Out-Null

if (-not $ResultsDir) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $ResultsDir = Join-Path $comparisonDir "results\$stamp"
}
$ResultsDir = [System.IO.Path]::GetFullPath($ResultsDir)
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$csvPath = Join-Path $ResultsDir 'runs.csv'

function Invoke-NativeChecked {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDirectory = '')
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath exited with code $LASTEXITCODE"
        }
    }
    finally {
        if ($WorkingDirectory) { Pop-Location }
    }
}

function Wait-Http {
    param([string]$Uri, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try { return Invoke-RestMethod -Uri $Uri -TimeoutSec 2 }
        catch { Start-Sleep -Milliseconds 300 }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for $Uri"
}

function Wait-SimulatorConnection {
    param([int]$TimeoutSeconds = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $stats = Invoke-RestMethod 'http://127.0.0.1:9091/stats'
        if ($stats.connections -eq 1) { return $stats }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Expected one simulator connection, found $($stats.connections)"
}

function Start-ControlledRun {
    param([int]$TargetEvents)
    Invoke-RestMethod -Method Post 'http://127.0.0.1:9091/control/reset' | Out-Null
    $body = @{ events = $TargetEvents } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $body 'http://127.0.0.1:9091/control/run' | Out-Null
}

function Wait-ControlledRun {
    param([int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $stats = Invoke-RestMethod 'http://127.0.0.1:9091/stats'
        if ($stats.state -eq 'complete') { return $stats }
        if ($stats.state -eq 'interrupted') { throw 'Simulator connection was interrupted' }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Controlled run timed out in state $($stats.state)"
}

function Get-Mean {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return 0.0 }
    return ($Values | Measure-Object -Average).Average
}

function Convert-MemoryToMB {
    param([string]$Value)
    if ($Value -notmatch '^\s*([0-9.]+)\s*([KMG]i?B)') { return 0.0 }
    $number = [double]$Matches[1]
    switch -Regex ($Matches[2]) {
        '^Ki?B$' { return $number / 1024 }
        '^Gi?B$' { return $number * 1024 }
        default { return $number }
    }
}

function Get-NatsSample {
    $raw = docker stats --no-stream --format '{{json .}}' nephtys_comparison_nats
    if ($LASTEXITCODE -ne 0 -or -not $raw) { throw 'docker stats failed' }
    $stats = $raw | ConvertFrom-Json
    $memoryPart = ($stats.MemUsage -split '/')[0].Trim()
    return [pscustomobject]@{
        RSSMB = Convert-MemoryToMB $memoryPart
        CPUPercent = [double](($stats.CPUPerc -replace '%', '').Trim())
    }
}

function Register-NephtysStream {
    $headers = @{ Authorization = 'Bearer bench' }
    $body = @{
        id = 'compare-nephtys'
        kind = 'websocket'
        url = 'ws://127.0.0.1:9091/ws'
        topic = 'nephtys.stream.compare.nephtys'
        pipeline = @{
            transform = @{ mapping = @{ station='station_id'; pm25='pm25'; no2='no2'; temp='temperature'; ts='ts' } }
            dedup = @{ enabled=$true; cache_size=500; ttl='30s' }
            threshold = @{ enabled=$true; path='pm25'; delta=1.0 }
            batch = @{ enabled=$true; max_batch_size=50; flush_interval='5s' }
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:3002/v1/streams' -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
}

function Reset-ToolPipeline {
    param([string]$System)
    if ($System -eq 'nephtys') {
        $headers = @{ Authorization = 'Bearer bench' }
        Invoke-RestMethod -Method Delete -Uri 'http://127.0.0.1:3002/v1/streams/compare-nephtys' -Headers $headers | Out-Null
        Register-NephtysStream
    }
    else {
        $flow = Get-Content -Raw (Join-Path $nodeRedDir 'flows.json')
        $headers = @{ 'Node-RED-Deployment-Type' = 'full' }
        Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:1880/flows' -Headers $headers -ContentType 'application/json' -Body $flow | Out-Null
    }
    Wait-SimulatorConnection | Out-Null
}

function Stop-ExactProcess {
    param($Process)
    if ($null -ne $Process) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        try { $Process.WaitForExit(5000) | Out-Null } catch {}
    }
}

function Start-Nats {
    docker compose -f $composeFile down --remove-orphans | Out-Null
    docker compose -f $composeFile up -d | Out-Null
    Wait-Http 'http://127.0.0.1:8322/healthz' 45 | Out-Null
}

function Stop-Nats {
    docker compose -f $composeFile down --remove-orphans | Out-Null
}

function Start-Collector {
    param([bool]$CreateStream, [string]$LogPrefix)
    $args = @('-nats','nats://127.0.0.1:4322','-http','127.0.0.1:9092',"-create-stream=$($CreateStream.ToString().ToLowerInvariant())")
    $process = Start-Process $collectorExe -ArgumentList $args -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$LogPrefix.collector.out" -RedirectStandardError "$LogPrefix.collector.err"
    Wait-Http 'http://127.0.0.1:9092/healthz' 15 | Out-Null
    return $process
}

function Start-Tool {
    param([string]$System, [string]$LogPrefix)
    if ($System -eq 'nephtys') {
        $oldNats = $env:NATS_URL; $oldPort = $env:NEPHTYS_PORT; $oldToken = $env:NEPHTYS_ADMIN_TOKEN
        $env:NATS_URL = 'nats://127.0.0.1:4322'; $env:NEPHTYS_PORT = '3002'; $env:NEPHTYS_ADMIN_TOKEN = 'bench'
        try {
            $process = Start-Process $nephtysExe -WindowStyle Hidden -PassThru `
                -RedirectStandardOutput "$LogPrefix.tool.out" -RedirectStandardError "$LogPrefix.tool.err"
        }
        finally {
            $env:NATS_URL = $oldNats; $env:NEPHTYS_PORT = $oldPort; $env:NEPHTYS_ADMIN_TOKEN = $oldToken
        }
        Wait-Http 'http://127.0.0.1:3002/health' 20 | Out-Null
        Register-NephtysStream
        return $process
    }

    $nodeExe = (Get-Command node).Source
    $redJS = Join-Path $nodeRedDir 'node_modules\node-red\red.js'
    $settings = Join-Path $nodeRedDir 'settings.js'
    $args = @($redJS, '--userDir', $nodeRedDir, '--settings', $settings)
    $process = Start-Process $nodeExe -ArgumentList $args -WorkingDirectory $nodeRedDir -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$LogPrefix.tool.out" -RedirectStandardError "$LogPrefix.tool.err"
    Wait-Http 'http://127.0.0.1:1880' 30 | Out-Null
    return $process
}

function Invoke-TrialAttempt {
    param([string]$System, [int]$Trial, [int]$Order, [int]$Attempt)
    $name = ('{0:D2}-{1}-trial-{2}-attempt-{3}' -f $Order, $System, $Trial, $Attempt)
    $prefix = Join-Path $ResultsDir $name
    $tool = $null; $collector = $null
    try {
        Start-Nats
        if ($System -eq 'nephtys') {
            $tool = Start-Tool $System $prefix
            $collector = Start-Collector $false $prefix
        }
        else {
            $collector = Start-Collector $true $prefix
            $tool = Start-Tool $System $prefix
        }
        Wait-SimulatorConnection | Out-Null

        Start-ControlledRun $WarmupEvents
        Wait-ControlledRun ([math]::Max(60, [int]($WarmupEvents / 20 * $IntervalMs / 1000 + 30))) | Out-Null
        Start-Sleep -Seconds 6
        Reset-ToolPipeline $System

        Invoke-RestMethod -Method Post "http://127.0.0.1:9092/reset?system=$System" | Out-Null
        Start-ControlledRun $Events

        $rss = [System.Collections.Generic.List[double]]::new()
        $cpu = [System.Collections.Generic.List[double]]::new()
        $natsRSS = [System.Collections.Generic.List[double]]::new()
        $natsCPU = [System.Collections.Generic.List[double]]::new()
        $stackRSS = [System.Collections.Generic.List[double]]::new()
        $previousCPU = $tool.TotalProcessorTime.TotalSeconds
        $previousAt = Get-Date
        $timeoutAt = (Get-Date).AddSeconds([math]::Max(120, [int]($Events / 20 * $IntervalMs / 1000 + 60)))
        $completeAt = $null

        while ((Get-Date) -lt $timeoutAt) {
            Start-Sleep -Seconds 1
            $tool.Refresh()
            if ($tool.HasExited) { throw "$System exited during measurement" }
            $now = Get-Date
            $currentCPU = $tool.TotalProcessorTime.TotalSeconds
            $elapsed = ($now - $previousAt).TotalSeconds
            if ($elapsed -gt 0) { $cpu.Add((($currentCPU - $previousCPU) / $elapsed) * 100.0) }
            $previousCPU = $currentCPU; $previousAt = $now
            $toolRSS = $tool.WorkingSet64 / 1MB
            $nats = Get-NatsSample
            $rss.Add($toolRSS); $natsRSS.Add($nats.RSSMB); $natsCPU.Add($nats.CPUPercent); $stackRSS.Add($toolRSS + $nats.RSSMB)

            $sim = Invoke-RestMethod 'http://127.0.0.1:9091/stats'
            if ($sim.state -eq 'interrupted') { throw 'Simulator connection interrupted during measurement' }
            if ($sim.state -eq 'complete') {
                if ($null -eq $completeAt) { $completeAt = Get-Date }
                if (((Get-Date) - $completeAt).TotalSeconds -ge 6) { break }
            }
        }
        if ($null -eq $completeAt) { throw 'Measurement timed out before source completion' }

        $sim = Invoke-RestMethod 'http://127.0.0.1:9091/stats'
        $output = Invoke-RestMethod "http://127.0.0.1:9092/snapshot?system=$System"
        if ($sim.events_sent -ne $Events) { throw "Expected $Events input events, observed $($sim.events_sent)" }
        if ($output.malformed_messages -ne 0) { throw "Collector observed $($output.malformed_messages) malformed messages" }
        if ($output.negative_latencies -ne 0) { throw "Collector observed $($output.negative_latencies) negative latencies" }
        if ($output.output_events -le 0 -or $output.output_messages -le 0) { throw 'No valid output was collected' }

        $started = ([datetime]$sim.started_at).ToUniversalTime()
        $completed = ([datetime]$sim.completed_at).ToUniversalTime()
        $duration = ($completed - $started).TotalSeconds
        $result = [ordered]@{
            valid = $true; invalid_reason = ''; system = $System; trial = $Trial; order = $Order; attempt = $Attempt
            timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
            duration_s = [math]::Round($duration, 6); input_events = [int64]$sim.events_sent; input_bytes = [int64]$sim.bytes_sent
            output_messages = [int64]$output.output_messages; output_payload_bytes = [int64]$output.output_payload_bytes; output_events = [int64]$output.output_events
            byte_reduction_pct = [math]::Round(100 * (1 - $output.output_payload_bytes / $sim.bytes_sent), 6)
            message_reduction_pct = [math]::Round(100 * (1 - $output.output_messages / $sim.events_sent), 6)
            throughput_eps = [math]::Round($sim.events_sent / $duration, 6); input_loss = $Events - $sim.events_sent
            tool_rss_mean_mb = [math]::Round((Get-Mean $rss.ToArray()), 6); tool_rss_peak_mb = [math]::Round(($rss | Measure-Object -Maximum).Maximum, 6)
            tool_cpu_mean_pct = [math]::Round((Get-Mean $cpu.ToArray()), 6)
            nats_rss_mean_mb = [math]::Round((Get-Mean $natsRSS.ToArray()), 6); nats_cpu_mean_pct = [math]::Round((Get-Mean $natsCPU.ToArray()), 6)
            stack_rss_mean_mb = [math]::Round((Get-Mean $stackRSS.ToArray()), 6)
            latency_p50_ms = [math]::Round([double]$output.latency_p50_ms, 6); latency_p95_ms = [math]::Round([double]$output.latency_p95_ms, 6)
            sequence_sha256 = [string]$output.sequence_sha256
        }
        $result | ConvertTo-Json -Depth 6 | Set-Content "$prefix.json"
        return [pscustomobject]$result
    }
    catch {
        $failure = [ordered]@{
            valid = $false; invalid_reason = $_.Exception.Message; system = $System; trial = $Trial; order = $Order; attempt = $Attempt
            timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        }
        $failure | ConvertTo-Json | Set-Content "$prefix.invalid.json"
        throw
    }
    finally {
        Stop-ExactProcess $tool
        Stop-ExactProcess $collector
        Stop-Nats
        $deadline = (Get-Date).AddSeconds(8)
        do {
            try { $connections = (Invoke-RestMethod 'http://127.0.0.1:9091/stats').connections } catch { $connections = 0 }
            if ($connections -eq 0) { break }
            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $deadline)
    }
}

# Validate and build every executable from pinned source.
$actualCommit = (git -C $NephtysSource rev-parse HEAD).Trim()
if ($actualCommit -ne $expectedNephtysCommit) { throw "Nephtys source is $actualCommit, expected $expectedNephtysCommit" }
$nodeVersion = (node --version).Trim()
if ($nodeVersion -ne 'v24.16.0') { throw "Node.js is $nodeVersion, expected v24.16.0" }
Invoke-NativeChecked 'npm' @('ci','--ignore-scripts') $nodeRedDir
$nephtysExe = Join-Path $tempBin 'nephtys.exe'
$simulatorExe = Join-Path $tempBin 'sensor-sim.exe'
$collectorExe = Join-Path $tempBin 'collector.exe'
Invoke-NativeChecked 'go' @('build','-o',$nephtysExe,'.\cmd\nephtys') $NephtysSource
Invoke-NativeChecked 'go' @('build','-o',$simulatorExe,'.') (Join-Path $root 'sensor-sim')
Invoke-NativeChecked 'go' @('build','-o',$collectorExe,'.') (Join-Path $comparisonDir 'collector')
docker version --format '{{.Server.Version}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is not running' }

$metadata = [ordered]@{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o'); nephtys_commit = $actualCommit
    node = $nodeVersion; node_red = '5.0.1'; nats_transport = '3.4.0'; nats_jetstream = '3.4.0'; nats_server = '2.14.3'
    events = $Events; warmup_events = $WarmupEvents; interval_ms = $IntervalMs; stations = 20; duplicate_ratio = 0.3; seed = 2646958770
    cpu_definition = '100 percent equals one logical CPU'; rss_definition = 'Windows WorkingSet64 for tool; Docker stats for NATS'
    threshold_semantics = 'global previous output at pinned Nephtys commit; Node-RED RBE deadbandEq with separate topics disabled'
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ResultsDir 'metadata.json')

$simLog = Join-Path $ResultsDir 'simulator'
$simulator = Start-Process $simulatorExe -ArgumentList @('-stations','20','-interval',$IntervalMs,'-dup-ratio','0.3','-seed','2646958770','-port','9091','-controlled') `
    -WindowStyle Hidden -PassThru -RedirectStandardOutput "$simLog.out" -RedirectStandardError "$simLog.err"
try {
    Wait-Http 'http://127.0.0.1:9091/stats' 15 | Out-Null
    $baseOrder = @(
        @{system='nephtys';trial=1}, @{system='nodered';trial=1},
        @{system='nodered';trial=2}, @{system='nephtys';trial=2},
        @{system='nephtys';trial=3}, @{system='nodered';trial=3}
    )
    if ($Trials -ne 3) {
        $baseOrder = @()
        for ($trial = 1; $trial -le $Trials; $trial++) {
            if ($trial % 2 -eq 1) { $baseOrder += @{system='nephtys';trial=$trial}, @{system='nodered';trial=$trial} }
            else { $baseOrder += @{system='nodered';trial=$trial}, @{system='nephtys';trial=$trial} }
        }
    }

    $order = 0
    foreach ($slot in $baseOrder) {
        $order++
        $valid = $false
        for ($attempt = 1; $attempt -le $MaxAttemptsPerSlot -and -not $valid; $attempt++) {
            try {
                Write-Host "==> Order $order/$($baseOrder.Count): $($slot.system) trial $($slot.trial), attempt $attempt"
                $result = Invoke-TrialAttempt $slot.system $slot.trial $order $attempt
                $result | Export-Csv -Path $csvPath -NoTypeInformation -Append
                $valid = $true
            }
            catch {
                Write-Warning $_.Exception.Message
            }
        }
        if (-not $valid) { throw "No valid result for $($slot.system) trial $($slot.trial)" }
    }

    Invoke-NativeChecked 'python' @((Join-Path $comparisonDir 'summarize-comparison.py'),$csvPath,'--output',(Join-Path $ResultsDir 'summary.md'))
    Write-Host "Comparison complete: $ResultsDir"
}
finally {
    Stop-ExactProcess $simulator
    Stop-Nats
}
