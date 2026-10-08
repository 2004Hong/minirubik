param(
    [string]$BaseFolder = '',
    [string]$OriginalExe = '',
    [string]$OptimizedExe = '',
    [string]$OutputRoot = (Join-Path $PSScriptRoot '../results/c_compare'),
    [ValidateRange(1,21)][int]$Repeats = 3
)
$ErrorActionPreference = 'Stop'
if (-not $BaseFolder) { $BaseFolder = Split-Path -Parent $PSScriptRoot }
if (-not $OriginalExe) { $OriginalExe=Join-Path $BaseFolder 'c檔/CAHw_IDA.exe' }
if (-not $OptimizedExe) { $OptimizedExe=Join-Path $BaseFolder 'c檔/CAHw_IDA_improve.exe' }
$versions = @(
    @{Name='Original'; Exe=$OriginalExe},
    @{Name='Optimized'; Exe=$OptimizedExe}
)
foreach ($version in $versions) {
    if (-not (Test-Path -LiteralPath $version.Exe -PathType Leaf)) {
        throw "Release executable not found: $($version.Exe). Build both projects in Release/x64 first."
    }
}
$tests = @(
    @{Name='solved'; Input='12345671111111'; Length=0},
    @{Name='short'; Input='25314672313211'; Length=1},
    @{Name='depth11'; Input='21345671111111'; Length=11}
)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$folder=Join-Path $OutputRoot ('c_compare_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $folder | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
$manifest=[ordered]@{
    date=(Get-Date -Format o); computer=$env:COMPUTERNAME
    processor=$env:PROCESSOR_IDENTIFIER; os=[Environment]::OSVersion.VersionString
    repeats=$Repeats; configuration='Release/x64 (user-built)'
    timing='Program-reported clock() interval around solve_ida; includes verbose per-bound statistics; excludes table construction and final replay.'
    binaries=@($versions | ForEach-Object { @{version=$_.Name; path=$_.Exe; sha256=(Get-FileHash -LiteralPath $_.Exe).Hash} })
}
[IO.File]::WriteAllText((Join-Path $folder 'manifest.json'),($manifest | ConvertTo-Json -Depth 5),$utf8)
$csv=Join-Path $folder 'results.csv'
$failed=0
foreach ($test in $tests) {
    for ($run=1; $run -le $Repeats; $run++) {
        foreach ($version in $versions) {
            $id=$test.Name+'_'+$version.Name+'_'+$run
            $outFile=Join-Path $folder ($id+'_stdout.txt')
            $errFile=Join-Path $folder ($id+'_stderr.txt')
            $reason=''; $exitCode=$null; $expanded=$null; $generated=$null; $seconds=$null; $length=$null
            try {
                $proc=[Diagnostics.Process]::new()
                $proc.StartInfo.FileName=$version.Exe
                $proc.StartInfo.Arguments=$test.Input+' 11'
                $proc.StartInfo.UseShellExecute=$false
                $proc.StartInfo.CreateNoWindow=$true
                $proc.StartInfo.RedirectStandardOutput=$true
                $proc.StartInfo.RedirectStandardError=$true
                if (-not $proc.Start()) { throw 'Could not start the program.' }
                $stdoutTask=$proc.StandardOutput.ReadToEndAsync()
                $stderrTask=$proc.StandardError.ReadToEndAsync()
                $proc.WaitForExit()
                $exitCode=$proc.ExitCode
                if ($null -eq $exitCode) {
                    throw 'Process exit code unavailable; keep logs and report this result for inspection.'
                }
                $stdout=$stdoutTask.Result
                $stderr=$stderrTask.Result
                [IO.File]::WriteAllText($outFile,$stdout,$utf8)
                [IO.File]::WriteAllText($errFile,$stderr,$utf8)
                [IO.File]::WriteAllText((Join-Path $folder ($id+'.txt')),('Version='+$version.Name+"`r`nInput="+$test.Input+"`r`nRun="+$run+"`r`nSTDOUT:`r`n"+$stdout+"`r`nSTDERR:`r`n"+$stderr+"`r`nExitCode="+$exitCode+"`r`n"),$utf8)
                if ($exitCode -ne 0) { throw "Program exit code $exitCode" }
                $lm=[regex]::Match($stderr,'solution_length=(\d+)')
                $stats=[regex]::Match($stderr,'total expanded=(\d+) generated=(\d+) cpu_seconds=([0-9.]+)')
                if (-not $lm.Success -or -not $stats.Success) { throw 'Missing solution length or search statistics.' }
                $length=[int]$lm.Groups[1].Value
                if ($length -ne $test.Length) { throw "Expected length $($test.Length), got $length" }
                $moves=@($stdout.Trim() -split '\s+' | Where-Object {$_})
                if ($moves.Count -ne $length -or @($moves | Where-Object {$_ -notmatch '^[RBD][2'']?$'}).Count) { throw 'Unexpected printed moves.' }
                $expanded=[long]$stats.Groups[1].Value
                $generated=[long]$stats.Groups[2].Value
                $seconds=[double]::Parse($stats.Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture)
            } catch { $reason=$_.Exception.Message; $failed++ }
            [pscustomobject]@{Case=$test.Name; Input=$test.Input; Version=$version.Name; Run=$run; SolutionLength=$length; Expanded=$expanded; Generated=$generated; SearchSeconds=$seconds; ExitCode=$exitCode; Pass=($reason -eq ''); Failure=$reason} | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 -Append
            if ($reason) { Write-Host "$id FAIL: $reason" }
            else { Write-Host "$id PASS expanded=$expanded generated=$generated seconds=$seconds" }
        }
    }
}
$rows=@(Import-Csv -LiteralPath $csv)
$summary=@(foreach ($test in $tests) {
    foreach ($version in $versions) {
        $group=@($rows | Where-Object {$_.Case -eq $test.Name -and $_.Version -eq $version.Name -and $_.Pass -eq 'True'})
        if ($group.Count -ne $Repeats) { continue }
        $times=@($group | ForEach-Object {[double]::Parse($_.SearchSeconds,[Globalization.CultureInfo]::InvariantCulture)} | Sort-Object)
        $mid=[int][Math]::Floor($times.Count/2)
        $median=if($times.Count % 2){$times[$mid]}else{($times[$mid-1]+$times[$mid])/2}
        [pscustomobject]@{Case=$test.Name; Input=$test.Input; Version=$version.Name; Runs=$group.Count; ExpandedValues=(@($group.Expanded | Sort-Object -Unique) -join ';'); GeneratedValues=(@($group.Generated | Sort-Object -Unique) -join ';'); MedianSearchSeconds=$median; MinSearchSeconds=$times[0]; MaxSearchSeconds=$times[-1]}
    }
})
$summary | Export-Csv -LiteralPath (Join-Path $folder 'summary.csv') -NoTypeInformation -Encoding UTF8
$summary | Format-Table Case,Version,ExpandedValues,GeneratedValues,MedianSearchSeconds -AutoSize
Write-Host "Results folder: $folder"
if ($failed) { throw "$failed run(s) failed. Keep the result folder for inspection." }
