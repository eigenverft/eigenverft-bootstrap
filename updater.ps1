function Get-ScriptfileFromGitHub()
{
 param(
    [string]$RootUrl = 'https://raw.githubusercontent.com',
    [string]$Organization = 'eigenverft',
    [string]$Repository = 'eigenverft-bootstrap',
    [string]$Directory = 'scripts',
    [string]$Branch = 'main',
    [string]$File = 'lib.ps1'

 )

  $ErrorActionPreference='Stop';
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
  $dst = Join-Path $env:LOCALAPPDATA "Programs\$Organization\$Repository\$Directory\$File";
  New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null;
  $url = "$RootUrl/$Organization/$Repository/refs/heads/$Branch/$Directory/$File";
  Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $dst;
}

function Get-ScriptfileFromGitHubxx()
{
 param(
    [Parameter(Mandatory=$true)]
    [string]$Url = 'https://raw.githubusercontent.com',
    [string]$Organization = 'eigenverft',
    [string]$Repository = 'eigenverft-bootstrap',
    [string]$Directory = 'updater',
    [string]$Branch = 'main',
    [string]$File = 'updater.ps1'

 )

  $ErrorActionPreference='Stop';
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
  $dst = Join-Path $env:LOCALAPPDATA 'Programs\eigenverft\eigenverft-bootstrap\updater.ps1';
  New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null;
  $url = 'https://raw.githubusercontent.com/eigenverft/eigenverft-bootstrap/refs/heads/main/updater.ps1';
  Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $dst;
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$dst)
}

Write-Host "Starting Eigenverft PowerShell updater..."
Get-ScriptfileFromGitHub

. "$PSScriptRoot\scripts\lib.ps1"

Read-Host "Press Enter to continue..."