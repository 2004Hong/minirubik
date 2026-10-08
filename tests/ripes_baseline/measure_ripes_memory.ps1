param(
    [Parameter(Mandatory = $true)]
    [string]$TestDirectory,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '../../results/ripes_baseline/memory'),
    [string]$RipesPath = 'C:\Ripes\Ripes.exe'
)

$ErrorActionPreference = 'Stop'
$testRoot = (Resolve-Path -LiteralPath $TestDirectory).Path
if (-not (Test-Path -LiteralPath $RipesPath -PathType Leaf)) {
    throw "Ripes executable not found: $RipesPath"
}
$cases = @(
    @{ Name = 'control'; Bytes = 4; File = 'ripes_memory_control_equal.s' },
    @{ Name = '1MiB'; Bytes = 1048576; File = 'ripes_memory_1MiB_equal.s' },
    @{ Name = '4MiB'; Bytes = 4194304; File = 'ripes_memory_4MiB_equal.s' }
)
foreach ($case in $cases) {
    if (-not (Test-Path -LiteralPath (Join-Path $testRoot $case.File) -PathType Leaf)) {
        throw "Missing source: $($case.File)"
    }
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$resultRoot = Join-Path $OutputRoot ('results_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $resultRoot | Out-Null
$metadata = @(
    "Started: $(Get-Date -Format o)",
    "Executable: $RipesPath",
    'Processor: RV32_ISS',
    'Metric: PrivateMemorySize64, bytes',
    'Sampling: approximately every 10 ms, including process startup',
    'Peak: highest observed sample, not an exact lifetime peak',
    'Fresh process per run; three runs per footprint; 1048576 stores per run'
)
foreach ($case in $cases) {
    $hash = Get-FileHash -LiteralPath (Join-Path $testRoot $case.File) -Algorithm SHA256
    $metadata += "$($case.File) SHA256: $($hash.Hash)"
}
$metadata | Set-Content -LiteralPath (Join-Path $resultRoot 'method.txt') -Encoding UTF8
$records = @()
foreach ($case in $cases) {
    for ($run = 1; $run -le 3; $run++) {
        $prefix = Join-Path $resultRoot ($case.Name + '_run' + $run)
        $source = Join-Path $testRoot $case.File
        $report = $prefix + '_ripes.txt'
        $arguments = @('--mode', 'cli', '--src', ('"' + $source + '"'),
            '-t', 'asm', '--proc', 'RV32_ISS', '--iret', '--exectime',
            '--timeout', '60000', '--output', ('"' + $report + '"'))
        Write-Host "Running $($case.Name), run $run/3..."
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process -FilePath $RipesPath -ArgumentList $arguments `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput ($prefix + '_stdout.txt') `
            -RedirectStandardError ($prefix + '_stderr.txt')
        # Retain the process handle before Refresh() and process termination.
        $processHandle = $process.Handle
        $samples = New-Object 'System.Collections.Generic.List[object]'
        $peak = [long]0
        try {
            while (-not $process.HasExited) {
                try {
                    $process.Refresh()
                    $bytes = [long]$process.PrivateMemorySize64
                    if ($bytes -gt 0) {
                        $samples.Add([pscustomobject]@{
                            ElapsedMs = $watch.ElapsedMilliseconds
                            PrivateBytes = $bytes
                        })
                        if ($bytes -gt $peak) { $peak = $bytes }
                    }
                } catch [System.InvalidOperationException] {
                    if (-not $process.HasExited) { throw }
                }
                Start-Sleep -Milliseconds 10
            }
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            $samples | Export-Csv -LiteralPath ($prefix + '_samples.csv') -NoTypeInformation -Encoding UTF8
            if ($null -ne $exitCode -and $exitCode -ne 0) {
                throw "Ripes failed (exit $exitCode). See $prefix`_stderr.txt"
            }
            $stdoutText = Get-Content -LiteralPath ($prefix + '_stdout.txt') -Raw
            if ($stdoutText -notmatch 'Program exited with code:\s*0\b') {
                throw "Successful guest exit was not reported. See $prefix`_stdout.txt and $prefix`_stderr.txt"
            }
            if ($samples.Count -eq 0) { throw 'No memory samples were captured.' }
            $reportText = Get-Content -LiteralPath $report -Raw
            if ($reportText -notmatch 'instructions retired\s+(\d+)') {
                throw "Missing completed instruction report: $report"
            }
            $instructions = [long]$Matches[1]
            $records += [pscustomobject]@{
                Test = $case.Name
                GuestBytes = $case.Bytes
                Run = $run
                SampledPeakPrivateBytes = $peak
                Samples = $samples.Count
                RetiredInstructions = $instructions
            }
            $records | Export-Csv -LiteralPath (Join-Path $resultRoot 'summary.csv') -NoTypeInformation -Encoding UTF8
            Write-Host "  sampled peak = $peak bytes; samples = $($samples.Count)"
        } finally {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
            $process.Dispose()
            $watch.Stop()
        }
    }
}
$medians = foreach ($case in $cases) {
    $values = @($records | Where-Object { $_.Test -eq $case.Name } |
        Sort-Object SampledPeakPrivateBytes)
    [pscustomobject]@{ Test = $case.Name; GuestBytes = $case.Bytes;
        MedianSampledPeakBytes = $values[1].SampledPeakPrivateBytes }
}
$medians | Export-Csv -LiteralPath (Join-Path $resultRoot 'medians.csv') -NoTypeInformation -Encoding UTF8
$records | Format-Table -AutoSize
$medians | Format-Table -AutoSize
Write-Host "Saved results: $resultRoot"
