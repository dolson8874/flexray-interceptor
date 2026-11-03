param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
foreach ($test in @('run_can_tx_diagnostics.ps1', 'run_protocol_tests.ps1',
                    'run_queue_tests.ps1', 'run_integration_tests.ps1', 'run_flexray_equivalence.ps1', 'run_control_snapshot_tests.ps1', 'run_review_regressions.ps1', 'run_remaining_review.ps1')) {
    & (Join-Path $PSScriptRoot $test) -VivadoBin $VivadoBin
}
Write-Output 'ALL_LOCAL_SIMULATIONS_PASS'
