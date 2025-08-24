# Eigenverft bootstrapper

## Windows Cmd:
Copy-paste the next line into **Command Prompt** (Win+R → `cmd` → Enter).  
It downloads `bootstrapper.cmd` to `%TEMP%`, runs it, deletes it, and then closes the window.

```
cmd /V:ON /C "set R=https://raw.githubusercontent.com& set O=eigenverft& set P=eigenverft-bootstrap& set B=main& set C=bootstrapper.cmd& set F=%TEMP%\bootstrapper_!RANDOM!!RANDOM!.cmd & curl.exe -fsSL !R!/!O!/!P!/refs/heads/!B!/!C! -o !F! && call !F! & del /Q !F! 2>nul" & exit
```

## Windows PowerShell:
Copy-paste the next line into **Windows PowerShell (PS5)**.  
It executes the remote bootstrapper and then exits the PowerShell session.

```
$R='https://raw.githubusercontent.com';$O='eigenverft';$P='eigenverft-bootstrap';$B='main';$C='bootstrapper.ps1'; irm "$R/$O/$P/refs/heads/$B/$C" | iex; exit
```
