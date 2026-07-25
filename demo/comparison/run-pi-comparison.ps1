[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PiHost,
    [string]$PiUser = 'pi',
    [Parameter(Mandatory)][string]$WindowsLanIp,
    [Parameter(Mandatory)][string]$PowerSampleScript,
    [Parameter(Mandatory)][string]$PowerMeterModel,
    [Parameter(Mandatory)][double]$PowerMeterResolutionWh,
    [Parameter(Mandatory)][double]$AmbientTemperatureC,
    [Parameter(Mandatory)][string]$OsImageRelease,
    [string]$StorageDescription = 'A2 microSD',
    [string]$NephtysSource = 'C:\dev\Nephtys-uic-benchmark',
    [int]$Events = 12000,
    [int]$WarmupEvents = 1200,
    [int]$Trials = 3,
    [int]$GoldenEvents = 120,
    [int]$MaxAttemptsPerSlot = 2,
    [string]$ResultsDir = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$expectedCommit = 'c146ee7c397fd415194635b0e872d30f3cc87c0a'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$comparison = $PSScriptRoot
$remote = "$PiUser@$PiHost"
$remoteRoot = '/home/' + $PiUser + '/nephtys-pi-bench'
$bin = Join-Path $env:TEMP 'nephtys-pi-comparison-bin'
New-Item -ItemType Directory -Force $bin | Out-Null
if (-not $ResultsDir) {
    $ResultsDir = Join-Path $comparison ('results\pi-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
}
New-Item -ItemType Directory -Force $ResultsDir | Out-Null
$PowerSampleScript = (Resolve-Path $PowerSampleScript).Path

function Invoke-Native([string]$File, [string[]]$Arguments, [string]$Directory = '') {
    if ($Directory) { Push-Location $Directory }
    try { & $File @Arguments; if ($LASTEXITCODE -ne 0) { throw "$File exited $LASTEXITCODE" } }
    finally { if ($Directory) { Pop-Location } }
}
function Invoke-Ssh([string]$Command) {
    # -n is required, not cosmetic. Without it ssh.exe forwards its inherited stdin to
    # the remote command; when the orchestrator runs detached with redirected output,
    # that handle never reaches EOF and ssh can block forever after the remote command
    # has already finished. Observed hanging the golden slot indefinitely on the
    # nats.err check. It matters most inside the measured sampling loop, where a stall
    # would silently corrupt a run rather than just delay it.
    $output = & ssh -n -o BatchMode=yes -o ConnectTimeout=10 $remote $Command
    if ($LASTEXITCODE -ne 0) { throw "SSH command failed: $Command" }
    return ($output -join "`n")
}
function Wait-Http([string]$Uri, [int]$Seconds = 30) {
    $end = (Get-Date).AddSeconds($Seconds)
    do { try { return Invoke-RestMethod $Uri -TimeoutSec 2 } catch { Start-Sleep -Milliseconds 300 } } while ((Get-Date) -lt $end)
    throw "Timed out waiting for $Uri"
}
function Get-PowerSample {
    $raw = & $PowerSampleScript
    $sample = $raw | ConvertFrom-Json
    if ($null -eq $sample.watts -or $null -eq $sample.energy_wh) { throw 'Power adapter must return watts and energy_wh' }
    return $sample
}
function Reset-Simulator([int]$Count) {
    Invoke-RestMethod -Method Post 'http://127.0.0.1:9091/control/reset' | Out-Null
    # The tool attaches its WebSocket client asynchronously once its stream is
    # registered, and the Pi takes longer to get there than the Windows host did, so
    # wait for the single expected client rather than asserting on it immediately. The
    # "exactly one client" gate is preserved: anything other than 1 still fails.
    $connections = 0
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $connections = (Invoke-RestMethod 'http://127.0.0.1:9091/stats').connections
        if ($connections -eq 1) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    if ($connections -ne 1) { throw "Expected one simulator client, found $connections" }
    Invoke-RestMethod -Method Post -ContentType application/json -Body (@{events=$Count}|ConvertTo-Json -Compress) 'http://127.0.0.1:9091/control/run' | Out-Null
}
function Wait-Simulator([int]$Seconds) {
    $end=(Get-Date).AddSeconds($Seconds)
    do {
        $s=Invoke-RestMethod 'http://127.0.0.1:9091/stats'
        if($s.state -eq 'complete'){return $s}
        if($s.state -eq 'interrupted'){throw 'Simulator connection interrupted'}
        Start-Sleep -Milliseconds 250
    } while((Get-Date)-lt $end)
    throw 'Simulator timed out'
}
function Register-Nephtys {
    $body=@{id='compare-nephtys';kind='websocket';url="ws://${WindowsLanIp}:9091/ws";topic='nephtys.stream.compare.nephtys';pipeline=@{
        transform=@{mapping=@{station='station_id';pm25='pm25';no2='no2';temp='temperature';ts='ts'}}
        dedup=@{enabled=$true;cache_size=500;ttl='30s'};threshold=@{enabled=$true;path='pm25';delta=1.0}
        batch=@{enabled=$true;max_batch_size=50;flush_interval='5s'}
    }}|ConvertTo-Json -Depth 10
    Invoke-RestMethod -Method Post -Headers @{Authorization='Bearer bench'} -ContentType application/json -Body $body "http://${PiHost}:3002/v1/streams" | Out-Null
}
function Reset-Tool([string]$System) {
    if($System -eq 'nephtys'){
        Invoke-RestMethod -Method Delete -Headers @{Authorization='Bearer bench'} "http://${PiHost}:3002/v1/streams/compare-nephtys" | Out-Null
        Register-Nephtys
    } else {
        $flow=Get-Content -Raw (Join-Path $bin 'flows-pi.json')
        Invoke-RestMethod -Method Post -Headers @{'Node-RED-Deployment-Type'='full'} -ContentType application/json -Body $flow "http://${PiHost}:1880/flows" | Out-Null
    }
    $end=(Get-Date).AddSeconds(15)
    do { $c=(Invoke-RestMethod 'http://127.0.0.1:9091/stats').connections; if($c -eq 1){return}; Start-Sleep -Milliseconds 250 } while((Get-Date)-lt $end)
    throw "Expected one simulator connection, found $c"
}
function Mean($Values) { if(-not $Values){return 0}; return ($Values|Measure-Object -Average).Average }
function Start-Collector([string]$Prefix,[bool]$CreateStream) {
    # Only one process may create the NEPHTYS JetStream stream. Nephtys creates it with
    # file storage; the collector would create it with memory storage, and the second
    # writer then fails AddStream with "stream name already in use" because the configs
    # differ. The Nephtys slots therefore let the tool own the stream, and the Node-RED
    # slots let the collector own it, matching run-comparison.ps1.
    $p=Start-Process (Join-Path $bin 'collector.exe') -ArgumentList @('-nats',"nats://${PiHost}:4322",'-http','127.0.0.1:9092',"-create-stream=$($CreateStream.ToString().ToLowerInvariant())") -PassThru -WindowStyle Hidden -RedirectStandardOutput "$Prefix.collector.out" -RedirectStandardError "$Prefix.collector.err"
    Wait-Http 'http://127.0.0.1:9092/healthz' 15 | Out-Null
    return $p
}
function Stop-Local($Process) { if($Process){Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue; try{$Process.WaitForExit(3000)|Out-Null}catch{}} }
function Start-Simulator([string]$LogDirectory) {
    $process=Start-Process (Join-Path $bin 'sensor-sim.exe') -ArgumentList @('-stations','20','-interval','500','-dup-ratio','0.3','-seed','2646958770','-port','9091','-controlled') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $LogDirectory 'simulator.out') -RedirectStandardError (Join-Path $LogDirectory 'simulator.err')
    Wait-Http 'http://127.0.0.1:9091/stats' 15|Out-Null
    return $process
}

function Invoke-Slot([string]$System,[int]$Trial,[int]$Order,[int]$Attempt,[int]$MeasuredEvents=$Events) {
    $prefix=Join-Path $ResultsDir ('{0:D2}-{1}-trial-{2}-attempt-{3}' -f $Order,$System,$Trial,$Attempt)
    $collector=$null
    try {
        Invoke-Ssh "$remoteRoot/pi/remote-control.sh stop-all" | Out-Null
        Invoke-Ssh "$remoteRoot/pi/remote-control.sh start-nats" | Out-Null
        Wait-Http "http://${PiHost}:8322/healthz" 20 | Out-Null
        if($System -eq 'nephtys'){
            Invoke-Ssh "$remoteRoot/pi/remote-control.sh start-nephtys" | Out-Null
            Wait-Http "http://${PiHost}:3002/health" 30 | Out-Null
            Register-Nephtys
            $collector=Start-Collector $prefix $false
        } else {
            $collector=Start-Collector $prefix $true
            Invoke-Ssh "$remoteRoot/pi/remote-control.sh start-nodered" | Out-Null
            Wait-Http "http://${PiHost}:1880" 45 | Out-Null
        }
        Reset-Simulator $WarmupEvents; Wait-Simulator ([math]::Ceiling($WarmupEvents/40)+20)|Out-Null
        Start-Sleep -Seconds 6
        Reset-Tool $System
        Invoke-RestMethod -Method Post "http://127.0.0.1:9092/reset?system=$System"|Out-Null
        Invoke-RestMethod -Method Post 'http://127.0.0.1:9091/control/reset'|Out-Null

        $samples=@(); $startPower=Get-PowerSample
        Reset-Simulator $MeasuredEvents
        $previous=$null
        do {
            $remoteSample=(Invoke-Ssh "$remoteRoot/pi/remote-control.sh sample")|ConvertFrom-Json
            if($null -eq $remoteSample.tool -or $null -eq $remoteSample.nats){throw 'Tool or NATS exited during the measured run'}
            $power=Get-PowerSample
            $now=[DateTimeOffset]::UtcNow
            $toolCpu=0.0;$natsCpu=0.0
            if($previous){
                $seconds=($now-$previous.time).TotalSeconds
                $toolCpu=100.0*(($remoteSample.tool.cpu_ticks-$previous.remote.tool.cpu_ticks)/$remoteSample.clock_ticks)/$seconds
                $natsCpu=100.0*(($remoteSample.nats.cpu_ticks-$previous.remote.nats.cpu_ticks)/$remoteSample.clock_ticks)/$seconds
            }
            $samples += [pscustomobject]@{timestamp_utc=$now.ToString('o');tool_rss_mb=$remoteSample.tool.rss_kb/1024;nats_rss_mb=$remoteSample.nats.rss_kb/1024;tool_cpu_percent=$toolCpu;nats_cpu_percent=$natsCpu;temperature_c=$remoteSample.temperature_c;frequency_khz=$remoteSample.frequency_khz;throttled=$remoteSample.throttled;watts=$power.watts;energy_wh=$power.energy_wh}
            $previous=@{time=$now;remote=$remoteSample}
            $state=(Invoke-RestMethod 'http://127.0.0.1:9091/stats').state
            if($state -eq 'interrupted'){throw 'Simulator interrupted'}
            if($state -ne 'complete'){Start-Sleep -Seconds 1}
        } while($state -ne 'complete')
        $sim=Wait-Simulator ([math]::Ceiling($MeasuredEvents/40)+30)
        Start-Sleep -Seconds 6
        $endPower=Get-PowerSample
        $output=Invoke-RestMethod "http://127.0.0.1:9092/snapshot?system=$System"
        if($output.malformed_messages -ne 0 -or $output.negative_latencies -ne 0){throw 'Collector observed malformed output or a negative latency'}
        Invoke-Ssh "! grep -Eiq 'fatal|panic|error' $remoteRoot/run/nats.err"|Out-Null
        $samples|Export-Csv "$prefix.samples.csv" -NoTypeInformation
        $throttled=@($samples|Where-Object {$_.throttled -ne '0x0'}).Count
        # The simulator reports these as started_at / completed_at (see sensor-sim runStats).
        $duration=(([datetime]$sim.completed_at).ToUniversalTime()-([datetime]$sim.started_at).ToUniversalTime()).TotalSeconds
        if($duration -le 0){throw "Simulator reported a non-positive run duration"}
        $energy=[double]$endPower.energy_wh-[double]$startPower.energy_wh
        $result=[ordered]@{order=$Order;system=$System;trial=$Trial;attempt=$Attempt;valid=($sim.events_sent-eq $MeasuredEvents -and $output.malformed_messages-eq 0 -and $throttled-eq 0 -and $energy-gt 0);invalid_reason='';input_events=$sim.events_sent;input_bytes=$sim.bytes_sent;output_messages=$output.output_messages;output_bytes=$output.output_payload_bytes;retained_events=$output.output_events;sequence_sha256=$output.sequence_sha256;throughput_eps=$sim.events_sent/$duration;byte_reduction_percent=100*(1-$output.output_payload_bytes/$sim.bytes_sent);message_reduction_percent=100*(1-$output.output_messages/$sim.events_sent);tool_rss_mean_mb=Mean @($samples.tool_rss_mb);tool_rss_peak_mb=($samples.tool_rss_mb|Measure-Object -Maximum).Maximum;nats_rss_mean_mb=Mean @($samples.nats_rss_mb);stack_rss_mean_mb=(Mean @($samples.tool_rss_mb))+(Mean @($samples.nats_rss_mb));tool_cpu_mean_percent=Mean @($samples|Select-Object -Skip 1 -ExpandProperty tool_cpu_percent);nats_cpu_mean_percent=Mean @($samples|Select-Object -Skip 1 -ExpandProperty nats_cpu_percent);latency_p50_ms=$output.latency_p50_ms;latency_p95_ms=$output.latency_p95_ms;temperature_mean_c=Mean @($samples.temperature_c);temperature_peak_c=($samples.temperature_c|Measure-Object -Maximum).Maximum;throttled_samples=$throttled;energy_wh=$energy;joules_per_input_event=($energy*3600/$sim.events_sent);power_mean_w=Mean @($samples.watts)}
        if(-not $result.valid){$result.invalid_reason='event loss, malformed output, throttling, or invalid power delta'}
        $result|ConvertTo-Json|Set-Content "$prefix.json"
        return [pscustomobject]$result
    } catch {
        $failed=[pscustomobject]@{order=$Order;system=$System;trial=$Trial;attempt=$Attempt;valid=$false;invalid_reason=$_.Exception.Message}
        $failed|ConvertTo-Json|Set-Content "$prefix.invalid.json"
        return $failed
    } finally {
        try { & scp -q -r "${remote}:${remoteRoot}/run" "$prefix.remote" | Out-Null } catch {}
        try { Invoke-Ssh "$remoteRoot/pi/remote-control.sh stop-all"|Out-Null } catch {}
        Stop-Local $collector
    }
}

if((git -C $NephtysSource rev-parse HEAD).Trim() -ne $expectedCommit){throw 'Nephtys source is not pinned to c146ee7'}
if(!(Test-Path $PowerSampleScript)){throw 'Power sample adapter not found'}
Invoke-Ssh 'true'|Out-Null
$oldGoos=$env:GOOS;$oldGoarch=$env:GOARCH;$oldCgo=$env:CGO_ENABLED
try{$env:GOOS='linux';$env:GOARCH='arm64';$env:CGO_ENABLED='0';Invoke-Native go @('build','-o',(Join-Path $bin 'nephtys'),'./cmd/nephtys') $NephtysSource}
finally{$env:GOOS=$oldGoos;$env:GOARCH=$oldGoarch;$env:CGO_ENABLED=$oldCgo}
Invoke-Native go @('build','-o',(Join-Path $bin 'sensor-sim.exe'),'.') (Join-Path $root 'sensor-sim')
Invoke-Native go @('build','-o',(Join-Path $bin 'collector.exe'),'.') (Join-Path $comparison 'collector')
$flow=(Get-Content -Raw (Join-Path $comparison 'nodered\flows.json')).Replace('ws://127.0.0.1:9091/ws',"ws://${WindowsLanIp}:9091/ws")
$flow|Set-Content (Join-Path $bin 'flows-pi.json')
Invoke-Native scp @((Join-Path $bin 'nephtys'),"${remote}:${remoteRoot}/bin/nephtys")
Invoke-Native scp @('-r',(Join-Path $comparison 'pi'),"${remote}:${remoteRoot}/")
Invoke-Native scp @((Join-Path $comparison 'nodered\package.json'),(Join-Path $comparison 'nodered\package-lock.json'),(Join-Path $comparison 'nodered\settings.js'),(Join-Path $bin 'flows-pi.json'),"${remote}:${remoteRoot}/nodered/")
Invoke-Ssh "chmod +x $remoteRoot/pi/*.sh $remoteRoot/bin/nephtys && mv $remoteRoot/nodered/flows-pi.json $remoteRoot/nodered/flows.json && cd $remoteRoot/nodered && PATH=$remoteRoot/node/bin:`$PATH npm ci --omit=dev"|Out-Null
$metadata=(Invoke-Ssh "$remoteRoot/pi/remote-control.sh metadata")|ConvertFrom-Json
$metadata|Add-Member -NotePropertyName timestamp_utc -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o'))
$metadata|Add-Member -NotePropertyName nephtys_commit -NotePropertyValue $expectedCommit
$metadata|Add-Member -NotePropertyName power_adapter -NotePropertyValue $PowerSampleScript
$metadata|Add-Member -NotePropertyName power_meter_model -NotePropertyValue $PowerMeterModel
$metadata|Add-Member -NotePropertyName power_meter_resolution_wh -NotePropertyValue $PowerMeterResolutionWh
$metadata|Add-Member -NotePropertyName ambient_temperature_c -NotePropertyValue $AmbientTemperatureC
$metadata|Add-Member -NotePropertyName os_image_release -NotePropertyValue $OsImageRelease
$metadata|Add-Member -NotePropertyName storage -NotePropertyValue $StorageDescription
$metadata|ConvertTo-Json|Set-Content (Join-Path $ResultsDir 'metadata.json')
$fullResultsDir=$ResultsDir
$goldenDir=Join-Path $ResultsDir 'golden'
New-Item -ItemType Directory -Force $goldenDir|Out-Null
$ResultsDir=$goldenDir
$golden=@()
foreach($system in @('nephtys','nodered')){
    $simulator=Start-Simulator $goldenDir
    try{$golden+=Invoke-Slot $system 0 ($golden.Count+1) 1 $GoldenEvents}
    finally{Stop-Local $simulator}
}
if(@($golden|Where-Object valid).Count-ne 2 -or $golden[0].sequence_sha256-ne $golden[1].sequence_sha256){throw 'ARM64 golden sequence validation failed'}
$golden|Export-Csv (Join-Path $goldenDir 'runs.csv') -NoTypeInformation
$ResultsDir=$fullResultsDir
$simulator=Start-Simulator $ResultsDir
try {
    $order=@();for($i=1;$i-le $Trials;$i++){if($i%2){$order+=@([pscustomobject]@{system='nephtys';trial=$i},[pscustomobject]@{system='nodered';trial=$i})}else{$order+=@([pscustomobject]@{system='nodered';trial=$i},[pscustomobject]@{system='nephtys';trial=$i})}}
    $results=@();$slot=0
    foreach($entry in $order){$slot++;for($attempt=1;$attempt-le $MaxAttemptsPerSlot;$attempt++){$r=Invoke-Slot $entry.system $entry.trial $slot $attempt;$results+=$r;if($r.valid){break}}}
    $results|Export-Csv (Join-Path $ResultsDir 'runs.csv') -NoTypeInformation
    $valid=@($results|Where-Object valid)
    foreach($trial in 1..$Trials){$pair=@($valid|Where-Object trial -eq $trial);if($pair.Count-ne 2 -or $pair[0].sequence_sha256-ne $pair[1].sequence_sha256){throw "Paired sequence mismatch in trial $trial"}}
    python (Join-Path $comparison 'summarize-pi-results.py') $ResultsDir
} finally {Stop-Local $simulator;try{Invoke-Ssh "$remoteRoot/pi/remote-control.sh stop-all"|Out-Null}catch{}}
