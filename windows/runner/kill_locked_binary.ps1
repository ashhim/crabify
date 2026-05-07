param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
)

$normalizedTarget = [System.IO.Path]::GetFullPath($TargetPath)

Get-Process | Where-Object {
    $_.Path -and
    ([string]::Equals(
        [System.IO.Path]::GetFullPath($_.Path),
        $normalizedTarget,
        [System.StringComparison]::OrdinalIgnoreCase
    ))
} | ForEach-Object {
    try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
    } catch {
    }
}
