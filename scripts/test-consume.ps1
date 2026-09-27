# End-to-end test of the consume folder: drops a fresh dummy PDF into paperless/consume
# and waits until Paperless has consumed it. Each run generates unique content (timestamp),
# because Paperless rejects files with an identical checksum as duplicates.
#
# Usage (from repo root):  powershell -ExecutionPolicy Bypass -File scripts\test-consume.ps1

param([int]$TimeoutSeconds = 120)

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$name = "consume-test-$stamp.pdf"
$text = "Paperless Consume-Test $stamp"

# Minimal single-page PDF with correct xref offsets
$objs = @(
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    $null,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
)
$stream = "BT /F1 24 Tf 72 750 Td ($text) Tj ET"
$objs[3] = "<< /Length $($stream.Length) >>`nstream`n$stream`nendstream"

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("%PDF-1.4`n")
$offsets = @()
for ($i = 0; $i -lt $objs.Count; $i++) {
    $offsets += $sb.Length
    [void]$sb.Append("$($i + 1) 0 obj`n$($objs[$i])`nendobj`n")
}
$xref = $sb.Length
[void]$sb.Append("xref`n0 $($objs.Count + 1)`n0000000000 65535 f `n")
foreach ($o in $offsets) { [void]$sb.Append(("{0:D10} 00000 n `n" -f $o)) }
[void]$sb.Append("trailer`n<< /Size $($objs.Count + 1) /Root 1 0 R >>`nstartxref`n$xref`n%%EOF`n")

$target = Join-Path $root "paperless\consume\$name"
[System.IO.File]::WriteAllText($target, $sb.ToString(), [System.Text.Encoding]::ASCII)
$start = Get-Date
Write-Host "Dropped $name at $($start.ToString('HH:mm:ss')) - waiting for Paperless..."

$since = $start.AddSeconds(-2).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$detected = $false
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
    Start-Sleep -Seconds 2
    $logs = docker compose logs --since $since paperless 2>$null | Select-String -SimpleMatch "consume-test-$stamp"
    if (-not $detected -and ($logs -match "task queue")) {
        $detected = $true
        Write-Host ("Detected after {0:N0}s" -f ((Get-Date) - $start).TotalSeconds)
    }
    if ($logs -match "consumption finished") {
        Write-Host ("Consumed after {0:N0}s" -f ((Get-Date) - $start).TotalSeconds) -ForegroundColor Green
        Write-Host "Note: paperless-gpt may rename it; search for 'Consume-Test $stamp' in Paperless."
        exit 0
    }
    if ($logs -match "duplicate|ERROR|failed") {
        $logs | Write-Host
        Write-Host "Consumption failed (see above)." -ForegroundColor Red
        exit 1
    }
}
if (Test-Path $target) { Write-Host "File was never picked up - it is still in the consume folder." -ForegroundColor Red }
else { Write-Host "Timed out after $TimeoutSeconds s waiting for the log confirmation." -ForegroundColor Red }
exit 1
