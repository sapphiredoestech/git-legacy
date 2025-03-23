@ECHO OFF
CALL %~dp0\InitializeEnvironment.bat || EXIT /b 10

IF "%1"=="" (SET "Configuration=Debug") ELSE (SET "Configuration=%1")

call %SCALAR_SCRIPTSDIR%\UninstallScalar.bat

if not exist "c:\Program Files\Git" goto :noGit
for /F "delims=" %%g in ('dir "c:\Program Files\Git\unins*.exe" /B /S /O:-D') do %%g /VERYSILENT /SUPPRESSMSGBOXES /NORESTART & goto :deleteGit

:deleteGit
rmdir /q/s "c:\Program Files\Git"

:noGit
REM This is a hacky way to sleep for 2 seconds in a non-interactive window.  The timeout command does not work if it can't redirect stdin.
ping 1.1.1.1 -n 1 -w 2000 >NUL

:runInstallers
call %SCALAR_OUTPUTDIR%\Scalar.Distribution.Windows\dist\%Configuration%\InstallScalar.bat
