function Wait-PressKey {
<#
.SYNOPSIS
Waits for a single key press (PS 5.1 and PS 7+ compatible).

.DESCRIPTION
Uses System.Console for true “any key” reads; falls back to Read-Host (Enter) in hosts without a real console.

.PARAMETER Message
Prompt to display.

.PARAMETER TimeoutSeconds
Optional timeout; 0 waits indefinitely.

.PARAMETER PassThru
Return the pressed key as [ConsoleKeyInfo].

.EXAMPLE
Wait-PressKey -Message 'Ready? Press any key...'

.EXAMPLE
$key = Wait-PressKey -PassThru
# Use $key.Key / $key.Modifiers as needed.
#>
    [CmdletBinding()]
    param(
        [string]$Message = 'Press any key to continue . . . ',
        [ValidateRange(0,86400)][int]$TimeoutSeconds = 0,
        [switch]$PassThru
    )

    try {
        if (-not [System.Console]::IsInputRedirected) {
            $old = [System.Console]::TreatControlCAsInput
            [System.Console]::TreatControlCAsInput = $true
            try {
                Write-Host $Message -NoNewline
                $key = $null
                if ($TimeoutSeconds -gt 0) {
                    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
                    while ([DateTime]::UtcNow -lt $deadline -and -not [System.Console]::KeyAvailable) {
                        Start-Sleep -Milliseconds 50
                    }
                    if ([System.Console]::KeyAvailable) { $key = [System.Console]::ReadKey($true) }
                } else {
                    $key = [System.Console]::ReadKey($true)
                }
                Write-Host
                if ($PassThru -and $key) { return $key }
                return
            }
            finally {
                [System.Console]::TreatControlCAsInput = $old
            }
        }
    } catch { }

    # Fallback (no real console: ISE/redirect/CI) — requires Enter.
    Write-Host ($Message + '(press Enter)') -NoNewline
    try { [void](Read-Host) } catch { }
    Write-Host
}
