param(
    [string]$SolverFile = (Join-Path $PSScriptRoot '../rv32i/final/cli.s'),
    [string]$RipesExe = 'C:\Ripes\Ripes.exe',
    [string[]]$Models = @('RV32_ISS','RV32_5S'),
    [ValidateRange(1,3)][int]$Count = 3,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '../results/models'),
    [int]$TimeoutSeconds = 600
)
$ErrorActionPreference = 'Stop'
foreach ($p in @($SolverFile,$RipesExe)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "File not found: $p" }
}
$SolverFile = (Resolve-Path -LiteralPath $SolverFile).Path
$source = [IO.File]::ReadAllText($SolverFile)
$rx = [regex]::new('(?m)(^\s*cube_input:\s*\r?\n\s*\.asciz\s*")[^"]*(")')
if ($rx.Matches($source).Count -ne 1) { throw 'Expected one cube_input string.' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$folder = Join-Path $OutputRoot ('models_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $folder | Out-Null
Copy-Item -LiteralPath $SolverFile -Destination (Join-Path $folder 'solver_snapshot.s')
$utf8 = [Text.UTF8Encoding]::new($false)
$manifest = @{solver=$SolverFile; solver_sha256=(Get-FileHash -LiteralPath $SolverFile).Hash; models=$Models; ripes_sha256=(Get-FileHash -LiteralPath $RipesExe).Hash}
[IO.File]::WriteAllText((Join-Path $folder 'manifest.json'),($manifest | ConvertTo-Json),$utf8)
$tests = @(
    @{Name='solved'; Input='12345671111111'; Length=0},
    @{Name='short'; Input='25314672313211'; Length=1},
    @{Name='depth11'; Input='21345671111111'; Length=11}
)
$csv = Join-Path $folder 'results.csv'
$failed = 0
foreach ($model in $Models) {
    if ($model -notin @('RV32_ISS','RV32_5S')) { throw "Unsupported model: $model" }
    foreach ($test in ($tests | Select-Object -First $Count)) {
        $inputText = $test.Input
        $replace = [Text.RegularExpressions.MatchEvaluator]{param($m) $m.Groups[1].Value+$inputText+$m.Groups[2].Value}
        [IO.File]::WriteAllText((Join-Path $folder 'current_case.s'),($rx.Replace($source,$replace)+"`n"),$utf8)
        $id = $model+'_'+$test.Name
        $consoleFile = Join-Path $folder ($id+'_console.txt')
        $errorFile = Join-Path $folder ($id+'_errors.txt')
        $metricName = $id+'_metrics.txt'
        $reason=''; $iret=$null; $cycles=$null; $cpi=$null
        Write-Host "Running $model $($test.Name)..."
        try {
            $argsText="--mode cli --src current_case.s -t asm --proc $model --iret --cycles --exectime --output $metricName"
            $proc=Start-Process -FilePath $RipesExe -WorkingDirectory $folder -ArgumentList $argsText -WindowStyle Hidden -PassThru -RedirectStandardOutput $consoleFile -RedirectStandardError $errorFile
            if (-not $proc.WaitForExit($TimeoutSeconds*1000)) { Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue; throw 'Timed out.' }
            $proc.WaitForExit()
            if ($null -ne $proc.ExitCode -and $proc.ExitCode -ne 0) { throw "Ripes exit code: $($proc.ExitCode)" }
            $console=[IO.File]::ReadAllText($consoleFile).Replace([string][char]0,'')
            $answer=[regex]::Match($console,'(?m)^\s*([01])\s+(\d+)\s+([01])\s*$')
            if (-not $answer.Success -or $answer.Groups[1].Value -ne '1' -or [int]$answer.Groups[2].Value -ne $test.Length -or $answer.Groups[3].Value -ne '1') { throw 'Unexpected found/length/replay result.' }
            if ($console -notmatch 'Program exited with code:\s*0') { throw 'Missing successful program exit.' }
            $moves=@($console -split '\r?\n' | Where-Object {$_.Trim() -match '^[RBD][2'']?(\s+[RBD][2'']?)*$'})
            if ($test.Length -eq 0) { if ($moves.Count -ne 0) { throw 'Unexpected moves for solved input.' } }
            elseif ($moves.Count -ne 1 -or @($moves[0].Trim() -split '\s+').Count -ne $test.Length) { throw 'Incorrect printed move count.' }
            $metrics=[IO.File]::ReadAllText((Join-Path $folder $metricName))
            $im=[regex]::Match($metrics,'instructions retired\s+(\d+)')
            $cm=[regex]::Match($metrics,'===== cycles\s+(\d+)')
            if (-not $im.Success -or -not $cm.Success) { throw 'Missing measurements.' }
            $iret=[long]$im.Groups[1].Value; $cycles=[long]$cm.Groups[1].Value
            $cpi=[Math]::Round($cycles/[double]$iret,6)
        } catch { $reason=$_.Exception.Message; $failed++ }
        [pscustomobject]@{Model=$model; Case=$test.Name; Input=$test.Input; ExpectedLength=$test.Length; Instructions=$iret; Cycles=$cycles; CPI=$cpi; Pass=($reason -eq ''); Failure=$reason} | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 -Append
        if ($reason) { Write-Host "FAIL $reason" } else { Write-Host "PASS instructions=$iret cycles=$cycles CPI=$cpi" }
    }
}
Write-Host "Results: $csv"
if ($failed) { throw "$failed test(s) failed; inspect logs." }
