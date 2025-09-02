  $ErrorActionPreference='Stop';
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
  $dst = Join-Path $env:LOCALAPPDATA 'Programs\eigenverft\eigenverft-bootstrap\source\eigenverft-updater.ps1';
  New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null;
  $url = 'https://raw.githubusercontent.com/eigenverft/eigenverft-bootstrap/refs/heads/main/source/eigenverft-updater.ps1';
  Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $dst;
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$dst)