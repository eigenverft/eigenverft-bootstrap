. "$PSScriptRoot/scripts/lib.ps1"
. "$PSScriptRoot/scripts/Out-Log.ps1"
. "$PSScriptRoot/scripts/Wait-PressKey.ps1"

Clear-Host

Start-Sleep -Milliseconds 500
Out-Log @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started.."
Start-Sleep -Milliseconds 500
Out-Log  @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started..."
Start-Sleep -Milliseconds 500


Wait-PressKey -Message 'Press any key to continue...'
