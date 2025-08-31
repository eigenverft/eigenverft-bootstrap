$WriteLogInlineDefaultsProgressBar = @{
    MinLevelPost    = 'Information'
    MinLevelFile    = 'Error'
    MinLevelConsole = 'Information'
    ConsoleOverwriteLastLine = $true
    ReturnJson    = $false
    Endpoint   = 'https://localhost:8080/api/logs'
    ApiKey     = 'your_api_key_here'
    LogSpace   = 'eigenverft-launcher'
}

$Logconfig = @{
    MinLevelPost  = 'Information'
    MinLevelFile  = 'Error'
    MinLevelConsole = 'Verbose'
    SuppressConsoleCaller = $false
    ConsoleUseShortDate = $false
    ConsoleOverwriteLastLine = $false
    ReturnJson    = $false
    Endpoint   = 'https://localhost:8080/api/logs'
    ApiKey     = 'your_api_key_here'
    LogSpace   = 'eigenverft-launcher'
}