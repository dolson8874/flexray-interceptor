param([Parameter(Mandatory=$true)][string]$Results)
$ErrorActionPreference = 'Stop'
$pending = @{}
$snapshots = [System.Collections.Generic.List[object]]::new()
$identities = [System.Collections.Generic.List[object]]::new()
$invalid = 0
foreach ($row in (Import-Csv (Join-Path $Results 'diagnostics.csv'))) {
    if ([int]$row.length -ne 8) { $invalid++; continue }
    $bytes = [byte[]]::new(8)
    for ($index = 0; $index -lt 8; $index++) { $bytes[$index] = [Convert]::ToByte($row.data_hex.Substring($index*2,2),16) }
    $time = [double]::Parse($row.time_s,[Globalization.CultureInfo]::InvariantCulture)
    if ($bytes[0] -eq 0x2F) {
        $identities.Add([pscustomobject]@{time_s=$time;source=[int]$row.source;firmware=('{0}.{1}.{2}' -f $bytes[1],$bytes[2],$bytes[3]);build_id=[BitConverter]::ToUInt32($bytes,4)})
        continue
    }
    if ($bytes[0] -lt 0x20 -or $bytes[0] -gt 0x27) { $invalid++; continue }
    $bus = $row.source
    $page = $bytes[0] - 0x20
    if (-not $pending.ContainsKey($bus) -or $pending[$bus].seq -ne $bytes[1] -or $time - $pending[$bus].time -gt 1.5) {
        $pending[$bus] = @{seq=$bytes[1];time=$time;mask=0;data=[byte[]]::new(48)}
    }
    $state = $pending[$bus]
    [Array]::Copy($bytes,2,$state.data,$page*6,6)
    $state.mask = $state.mask -bor (1 -shl $page)
    if ($state.mask -eq 255) {
        $values = [uint32[]]::new(12)
        for ($index = 0; $index -lt 12; $index++) { $values[$index] = [BitConverter]::ToUInt32($state.data,$index*4) }
        $snapshots.Add([pscustomobject]@{time_s=$state.time;source=[int]$bus;seq=$state.seq;dadc_frames=$values[0];bcm_frames=$values[1];dadc_drop=$values[2];bcm_drop=$values[3];dadc_peak=($values[4] -band 65535);bcm_peak=($values[4] -shr 16);fifo_level=$values[5];fifo_peak=$values[6];fifo_full_events=$values[7];dadc_bytes=$values[8];bcm_bytes=$values[9];spi_valid_bytes=$values[10];spi_clocked_bytes=$values[11]})
        $pending.Remove($bus)
    }
}
$snapshots | Export-Csv (Join-Path $Results 'snapshots.csv') -NoTypeInformation
$identities | Export-Csv (Join-Path $Results 'firmware.csv') -NoTypeInformation
$first=$snapshots[0];$last=$snapshots[$snapshots.Count-1]
$dt=$last.time_s-$first.time_s
$summary=[ordered]@{complete_snapshots=$snapshots.Count;identity_records=$identities.Count;invalid_records=$invalid;first=$first;last=$last;interval_s=$dt;dadc_input_Bps=([double]($last.dadc_bytes-$first.dadc_bytes)/$dt);bcm_input_Bps=([double]($last.bcm_bytes-$first.bcm_bytes)/$dt);dadc_fps=([double]($last.dadc_frames-$first.dadc_frames)/$dt);bcm_fps=([double]($last.bcm_frames-$first.bcm_frames)/$dt);dadc_drop_delta=($last.dadc_drop-$first.dadc_drop);bcm_drop_delta=($last.bcm_drop-$first.bcm_drop);spi_valid_delta=($last.spi_valid_bytes-$first.spi_valid_bytes);spi_clocked_delta=($last.spi_clocked_bytes-$first.spi_clocked_bytes)}
$summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Results 'diagnostic_summary.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 5
