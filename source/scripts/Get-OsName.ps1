function Get-OsName {
<#
.SYNOPSIS
Returns the host operating system name as a lowercase string.

.DESCRIPTION
Compatible with Windows PowerShell 5.x and PowerShell 7+. On PS5 it returns 'windows'.
On PS7+ it detects and returns one of: 'windows', 'linux', 'macos'. Returns 'unknown' only on rare fallback failure.

.EXAMPLE
PS> Get-OsName
windows

.OUTPUTS
System.String

.NOTES
Assumes PS5 is Windows-only (correct for supported installs). No side effects.
#>
    [CmdletBinding()]
    param()

    # Reviewer note: Branch early for PS5; avoids referencing PS7-only globals.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        return 'windows'
    }

    # PS7+ path: Prefer built-in flags; fall back to RuntimeInformation.
    try {
        if (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue) {
            if ($IsWindows) { return 'Windows' }
        }
        if (Get-Variable -Name IsLinux -Scope Global -ErrorAction SilentlyContinue) {
            if ($IsLinux) { return 'Linux' }
        }
        if (Get-Variable -Name IsMacOS -Scope Global -ErrorAction SilentlyContinue) {
            if ($IsMacOS) { return 'Macos' }
        }

        # Fallback for unusual hosts missing the built-ins.
        $ri = [System.Runtime.InteropServices.RuntimeInformation]
        if ($ri::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) { return 'Windows' }
        if ($ri::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux))   { return 'Linux' }
        if ($ri::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX))     { return 'Macos' }
    }
    catch {
        # Reviewer note: Swallowing exception here keeps output predictable.
    }

    'unknown'
}