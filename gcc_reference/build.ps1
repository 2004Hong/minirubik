param([string]$ToolchainBin = '')
$ErrorActionPreference = 'Stop'
if (-not $ToolchainBin) {
    $found = Get-Command riscv-none-elf-gcc.exe -ErrorAction SilentlyContinue
    if (-not $found) { $found = Get-Command riscv64-unknown-elf-gcc.exe -ErrorAction SilentlyContinue }
    if (-not $found) { throw 'Specify -ToolchainBin with the RISC-V GCC bin directory.' }
    $ToolchainBin = Split-Path -Parent $found.Source
}
$prefix = 'riscv-none-elf'
if (-not (Test-Path -LiteralPath (Join-Path $ToolchainBin ($prefix+'-gcc.exe')))) { $prefix = 'riscv64-unknown-elf' }
$gcc = Join-Path $ToolchainBin ($prefix+'-gcc.exe')
$size = Join-Path $ToolchainBin ($prefix+'-size.exe')
foreach ($tool in @($gcc,$size)) { if (-not (Test-Path -LiteralPath $tool)) { throw "Missing tool: $tool" } }
$resultsFolder = Join-Path $PSScriptRoot 'results'
New-Item -ItemType Directory -Path $resultsFolder -Force | Out-Null
Push-Location $PSScriptRoot
try {
    & $gcc --version | Out-File -LiteralPath (Join-Path $resultsFolder 'compiler_version.txt') -Encoding utf8
    & $gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding -fno-builtin -msmall-data-limit=0 -S solver_gcc_rv32i.c -o solver_gcc_rv32i.s
    if ($LASTEXITCODE -ne 0) { throw 'C compilation failed.' }
    & $gcc -march=rv32i -mabi=ilp32 -nostdlib '-Wl,--no-relax' '-Wl,-T,gcc_link.ld' gcc_start.s solver_gcc_rv32i.s -o solver_gcc_rv32i.elf
    if ($LASTEXITCODE -ne 0) { throw 'Assembly/link failed.' }
    $report = & $size -A solver_gcc_rv32i.elf
    if ($LASTEXITCODE -ne 0) { throw 'Size measurement failed.' }
    $report | Out-File -LiteralPath (Join-Path $resultsFolder 'gcc_size.txt') -Encoding utf8
    $report
} finally { Pop-Location }
