@echo off
rem newleaf for Codex on Windows. Codex runs a Windows hook as
rem   cmd.exe /C "<commandWindows>"
rem and this script runs the same bash hook, hooks\<name>.sh, with Git Bash.
rem cmd hands the hook's stdin and stdout through untouched. Git Bash comes from
rem CLAUDE_CODE_GIT_BASH_PATH if set, else from next to the git on PATH
rem (Git\cmd\git.exe or Git\mingw64\bin\git.exe). No Git Bash: nothing happens.
setlocal
set "NEWLEAF_BASH=%CLAUDE_CODE_GIT_BASH_PATH%"
if defined NEWLEAF_BASH if exist "%NEWLEAF_BASH%" goto run
set "NEWLEAF_BASH="
for /f "delims=" %%G in ('where git 2^>nul') do (
  if exist "%%~dpG..\bin\bash.exe" set "NEWLEAF_BASH=%%~dpG..\bin\bash.exe"
  if not defined NEWLEAF_BASH if exist "%%~dpG..\..\bin\bash.exe" set "NEWLEAF_BASH=%%~dpG..\..\bin\bash.exe"
  if defined NEWLEAF_BASH goto run
)
exit /b 0
:run
"%NEWLEAF_BASH%" "%~dp0%~1.sh"
