@echo on

set "BAZEL_OUTPUT_USER_ROOT=%TEMP%\copybara-bazel-output"
if not exist "%BAZEL_OUTPUT_USER_ROOT%" mkdir "%BAZEL_OUTPUT_USER_ROOT%"

:: Build copybara using Bazel.
bazel "--output_user_root=%BAZEL_OUTPUT_USER_ROOT%" build //java/com/google/copybara:copybara_deploy.jar ^
    --java_runtime_version=21 ^
    --tool_java_runtime_version=21 ^
    --repo_contents_cache= ^
    --stamp ^
    --embed_label=%PKG_VERSION% ^
    --verbose_failures
if errorlevel 1 exit /b 1

:: Install the JAR.
if not exist "%PREFIX%\share\copybara" mkdir "%PREFIX%\share\copybara"
copy /Y "bazel-bin\java\com\google\copybara\copybara_deploy.jar" "%PREFIX%\share\copybara\"
if errorlevel 1 exit /b 1

:: Create wrapper script.
if not exist "%PREFIX%\bin" mkdir "%PREFIX%\bin"
(
  echo @echo off
  echo setlocal
  echo if "%%HOME%%"=="" set "HOME=%%USERPROFILE%%"
  echo set "COPYBARA_PREFIX=%%~dp0.."
  echo set "JAVA_EXE=%%COPYBARA_PREFIX%%\Library\bin\java.exe"
  echo if not exist "%%JAVA_EXE%%" set "JAVA_EXE=java"
  echo "%%JAVA_EXE%%" -jar "%%COPYBARA_PREFIX%%\share\copybara\copybara_deploy.jar" %%*
  echo exit /b %%ERRORLEVEL%%
) > "%PREFIX%\bin\copybara.bat"
if errorlevel 1 exit /b 1

:: Collect licenses from all dependencies.
:: Keep PowerShell's caches outside SRC_DIR so Windows can remove the work tree.
set "COPYBARA_APPDATA_ROOT=%TEMP%\copybara-appdata-%PKG_VERSION%"
set "LOCALAPPDATA=%COPYBARA_APPDATA_ROOT%\Local"
set "APPDATA=%COPYBARA_APPDATA_ROOT%\Roaming"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%APPDATA%" mkdir "%APPDATA%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RECIPE_DIR%\collect_licenses.ps1"
if errorlevel 1 exit /b 1
