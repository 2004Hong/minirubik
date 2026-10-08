param(
    [ValidateSet('final','baseline','opt1','opt2')][string]$Version = 'final',
    [ValidateSet(0,1)][int]$Render = 0,
    [string]$InputState = '25314672313211',
    [ValidateRange(0,20)][int]$MatrixIndex = 1,
    [string]$OutputFile = ''
)
$ErrorActionPreference = 'Stop'
if ($InputState -notmatch '^[1-7]{7}[1-3]{7}$') { throw 'Expected a 14-character cube state.' }
if (@($InputState.Substring(0,7).ToCharArray() | Sort-Object -Unique).Count -ne 7) { throw 'Invalid permutation.' }
$sum=0
foreach ($digit in $InputState.Substring(7).ToCharArray()) { $sum += [int]$digit-[int][char]'1' }
if ($sum % 3) { throw 'Invalid orientation sum.' }
if (-not $OutputFile) {
    $name=if ($Render) {'led.s'} else {'cli.s'}
    $OutputFile=Join-Path $PSScriptRoot $name
}
if ($Version -ne 'final' -and $Render) { throw 'Historical versions do not contain a renderer. Use -Version final -Render 1.' }
if ($Version -eq 'final') {
    $sourcePath=Join-Path $PSScriptRoot 'solver.s'
} else {
    $sourcePath=Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'history') ($Version+'.s')
}
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Source file not found: $sourcePath" }
$lines=[IO.File]::ReadAllLines($sourcePath)
$result=[Collections.Generic.List[string]]::new()
$inside=$false
foreach ($line in $lines) {
    if ($line -eq '# @RENDER_BEGIN') {
        if ($inside) { throw 'Nested renderer block.' }
        $inside=$true; continue
    }
    if ($line -eq '# @RENDER_END') {
        if (-not $inside) { throw 'Unmatched renderer end.' }
        $inside=$false; continue
    }
    if (-not $inside -or $Render) { $result.Add($line) }
}
if ($inside) { throw 'Unclosed renderer block.' }
$source=$result -join "`n"
$rx=[regex]::new('(?m)(^\s*cube_input:\s*\r?\n\s*\.asciz\s*")[^"]*(")')
if ($rx.Matches($source).Count -ne 1) { throw 'Expected exactly one cube_input string.' }
$replace=[Text.RegularExpressions.MatchEvaluator]{param($m) $m.Groups[1].Value+$InputState+$m.Groups[2].Value}
$source=$rx.Replace($source,$replace)
$source=$source.Replace('LED_MATRIX_1_',('LED_MATRIX_'+$MatrixIndex+'_'))
$source=$source.Replace('# GUI: LED Matrix 1, Width 35, Height 25. Generate cli.s with build.ps1 -Render 0 for CLI metrics.',('# Generated from solver.s. RENDER='+$Render+'. LED Matrix '+$MatrixIndex+', Width 35, Height 25.'))
[IO.File]::WriteAllText($OutputFile,($source+"`n"),[Text.UTF8Encoding]::new($false))
Write-Host "Version=$Version source=$sourcePath RENDER=$Render output=$OutputFile"
