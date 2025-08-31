. "$PSScriptRoot/scripts/lib.ps1"
. "$PSScriptRoot/scripts/Out-Log.ps1"
. "$PSScriptRoot/scripts/Wait-PressKey.ps1"
. "$PSScriptRoot/scripts/Get-OsName.ps1"
. "$PSScriptRoot/scripts/Invoke-CSharpCompilationEx.ps1"

. "$PSScriptRoot/launcher.config.ps1"


Clear-Host

Out-Log @Logconfig -Level Information -Template "{Name} {State}." -Params @{ Name = 'eigenverft-bootstrappeer'; State = 'started' }

$osName = Get-OsName

Out-Log @Logconfig -Level Information -Template "Detecting operating system. {OsName}" -Params @{ OsName = $osName }

if ($osName -notlike 'windows') {
    Out-Log @Logconfig -Level Warning -Template "This script is designed for Windows PowerShell. Compatibility on {OsName} is not supported." -Params @{ OsName = $osName }
    exit 1
}


try {
    $r = Invoke-BuildIfRequired -SourceDir $PWD\source\src -AssemblyName MyApp -ThisVersion 1.2.3.6 -OutPath .\out -Quiet
    & $r.Executable.FullName
}
catch {
    Out-Log @Logconfig -Level Error -Template "Error: @Messsage: {ExceptionMessage} @Script: {ExceptionScriptName} @Line: {ExceptionLineNumber} @At: {ExceptionLine}" -Params @{ ExceptionMessage = $_.Exception.Message; ExceptionScriptName = $_.InvocationInfo.ScriptName ; ExceptionLineNumber = $_.InvocationInfo.ScriptLineNumber ; ExceptionLine = $_.InvocationInfo.Line.Trim() }
}

# ---- resolve expected EXE path ----


#$r = Set-AssemblyVersionAttributes -Path .\source\src -Version 1.2.3.4
#$artifact = Invoke-CSharpCompilationEx -Source .\source\src -OutputType WindowsApplication -AssemblyName MyApp -OutputPath .\out -Configuration Release -PdbType None
#& $artifact.Artifact.FullName

Start-Sleep -Milliseconds 500
Out-Log @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started." -InitialWrite
Start-Sleep -Milliseconds 500
Out-Log  @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started.."
Start-Sleep -Milliseconds 500
Out-Log  @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started..."


Wait-PressKey -Message 'Press any key to continue...'
