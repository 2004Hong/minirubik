param(
    [string]$RipesExe = 'C:\Ripes\Ripes.exe',
    [string]$SolverFile = (Join-Path $PSScriptRoot '../rv32i/final/cli.s'),
    [string]$InputsFile = (Join-Path $PSScriptRoot 'depth11_inputs.txt'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '../results/depth11'),
    [ValidateRange(1,2644)][int]$Count = 5,
    [ValidateRange(1,2644)][int]$StartIndex = 1,
    [ValidateRange(10,3600)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
foreach ($taskPath in @($RipesExe, $SolverFile, $InputsFile)) {
    if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
        throw "File not found: $taskPath"
    }
}
$SolverFile = (Resolve-Path -LiteralPath $SolverFile).Path
$InputsFile = (Resolve-Path -LiteralPath $InputsFile).Path
$RipesExe = (Resolve-Path -LiteralPath $RipesExe).Path
$cases = @(Get-Content -LiteralPath $InputsFile | ForEach-Object { $_.Trim() })
if ($cases.Count -ne 2644 -or @($cases | Sort-Object -Unique).Count -ne 2644) {
    throw 'Input file must contain exactly 2644 unique lines.'
}
foreach ($case in $cases) {
    if ($case -notmatch '^[1-7]{7}[1-3]{7}$') { throw "Invalid input format: $case" }
    if (@($case.Substring(0,7).ToCharArray() | Sort-Object -Unique).Count -ne 7) {
        throw "Invalid permutation: $case"
    }
    $sum = 0
    foreach ($digit in $case.Substring(7).ToCharArray()) { $sum += [int]$digit - [int][char]'1' }
    if ($sum % 3 -ne 0) { throw "Invalid orientation: $case" }
}
if ($StartIndex + $Count - 1 -gt $cases.Count) { throw 'Requested range exceeds 2644 inputs.' }
$source = [IO.File]::ReadAllText($SolverFile)
$pattern = '(?m)(^\s*cube_input:\s*\r?\n\s*\.asciz\s*")[^"]*(")'
$inputRegex = [regex]::new($pattern)
if ($inputRegex.Matches($source).Count -ne 1) {
    throw 'Expected exactly one cube_input label followed by .asciz.'
}
# Each run gets its own folder, original solver and previous logs stay intact.
$parent = $OutputRoot
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$runName = 'depth11_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
$runDir = Join-Path $parent $runName
New-Item -ItemType Directory -Path $runDir | Out-Null
Copy-Item -LiteralPath $SolverFile -Destination (Join-Path $runDir 'solver_snapshot.s')
Copy-Item -LiteralPath $InputsFile -Destination (Join-Path $runDir 'inputs_snapshot.txt')
$csvFile = Join-Path $runDir 'results.csv'
$encoding = [Text.UTF8Encoding]::new($false)
$manifest = [ordered]@{
    model = 'RV32_ISS'; solver = $SolverFile
    solver_sha256 = (Get-FileHash -LiteralPath $SolverFile -Algorithm SHA256).Hash
    inputs_sha256 = (Get-FileHash -LiteralPath $InputsFile -Algorithm SHA256).Hash
    ripes = $RipesExe
    ripes_sha256 = (Get-FileHash -LiteralPath $RipesExe -Algorithm SHA256).Hash
    start_index = $StartIndex; count = $Count; instruction_limit = 50000000
}
[IO.File]::WriteAllText((Join-Path $runDir 'manifest.json'), ($manifest | ConvertTo-Json), $encoding)
$passed = 0; $failed = 0
for ($index = $StartIndex - 1; $index -lt $StartIndex - 1 + $Count; ++$index) {
    $inputText = $cases[$index]
    $replaceInput = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $match.Groups[1].Value + $inputText + $match.Groups[2].Value
    }
    $testSource = $inputRegex.Replace($source, $replaceInput)
    [IO.File]::WriteAllText((Join-Path $runDir 'current_case.s'), $testSource + "`n", $encoding)
    $id = '{0:D4}' -f ($index + 1)
    $metricName = "case_${id}_metrics.txt"
    $consolePath = Join-Path $runDir "case_${id}_console.txt"
    $errorPath = Join-Path $runDir "case_${id}_errors.txt"
    $reason = ''; $found = ''; $length = ''; $replay = ''
    $instructions = $null; $cycles = $null; $milliseconds = $null
    $process = $null
    try {
        $argsText = "--mode cli --src current_case.s -t asm --proc RV32_ISS --iret --exectime --cycles --output $metricName"
        $process = Start-Process -FilePath $RipesExe -WorkingDirectory $runDir -ArgumentList $argsText -WindowStyle Hidden -PassThru -RedirectStandardOutput $consolePath -RedirectStandardError $errorPath
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
            throw "Case exceeded $TimeoutSeconds seconds."
        }
        $process.WaitForExit()
        # Windows PowerShell may return no ExitCode on this process object.
        # Do not treat a missing value as a nonzero exit; validate logs below.
        if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
            throw "Ripes process exit code: $($process.ExitCode)"
        }
        $console = [IO.File]::ReadAllText($consolePath).Replace([string][char]0, '')
        $errors = [IO.File]::ReadAllText($errorPath)
        if ($errors -match '(?i)\bERROR\b') { throw "Ripes error: $errors" }
        $answer = [regex]::Match($console, '(?m)^\s*([01])\s+(\d+)\s+([01])\s*$')
        if (-not $answer.Success) { throw 'Missing found/length/replay output.' }
        $found = $answer.Groups[1].Value
        $length = $answer.Groups[2].Value
        $replay = $answer.Groups[3].Value
        if ($found -ne '1' -or $length -ne '11' -or $replay -ne '1') {
            throw "Expected 1 11 1, got $found $length $replay."
        }
        if ($console -notmatch 'Program exited with code:\s*0') { throw 'Missing successful program exit.' }
        $moveLine = @($console -split '\r?\n' | Where-Object {
            $_.Trim() -match '^[RBD][2'']?(\s+[RBD][2'']?)*$'
        })
        if ($moveLine.Count -ne 1 -or @($moveLine[0].Trim() -split '\s+').Count -ne 11) {
            throw 'Expected exactly 11 printed moves.'
        }
        $metrics = [IO.File]::ReadAllText((Join-Path $runDir $metricName))
        $iret = [regex]::Match($metrics, 'instructions retired\s+(\d+)')
        $cycleMatch = [regex]::Match($metrics, '===== cycles\s+(\d+)')
        $timeMatch = [regex]::Match($metrics, 'execution time \(ms\)\s+(\d+)')
        if (-not $iret.Success -or -not $cycleMatch.Success) { throw 'Missing instruction/cycle measurements.' }
        $instructions = [long]$iret.Groups[1].Value
        $cycles = [long]$cycleMatch.Groups[1].Value
        if ($timeMatch.Success) { $milliseconds = [long]$timeMatch.Groups[1].Value }
        if ($instructions -gt 50000000) { throw 'Instruction count exceeds 50000000.' }
    } catch {
        $reason = $_.Exception.Message
    }
    $ok = $reason -eq ''
    if ($ok) { ++$passed } else { ++$failed }
    [pscustomobject]@{
        Case = $index + 1; Input = $inputText; Found = $found; Length = $length
        Replay = $replay; Instructions = $instructions; Cycles = $cycles
        SimulatorMs = $milliseconds; Pass = $ok; Failure = $reason
    } | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding UTF8 -Append
    if ($ok) {
        Write-Host "[$($index + 1)/2644] PASS $inputText instructions=$instructions"
    } else {
        Write-Host "[$($index + 1)/2644] FAIL $inputText $reason"
    }
}
$records = @(Import-Csv -LiteralPath $csvFile)
$measured = @($records | Where-Object { $_.Instructions -match '^\d+$' })
$worst = $measured | Sort-Object { [long]$_.Instructions } -Descending | Select-Object -First 1
Write-Host "Completed: passed=$passed failed=$failed tested=$Count"
if ($worst) { Write-Host "Largest measured count: $($worst.Instructions), input=$($worst.Input)" }
Write-Host "Results: $csvFile"
if ($failed -gt 0) { throw "$failed case(s) failed; inspect results.csv and case logs." }
