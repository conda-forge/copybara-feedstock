@echo on

set "BAZEL_OUTPUT_USER_ROOT=%TEMP%\copybara-bazel-output"
if not exist "%BAZEL_OUTPUT_USER_ROOT%" mkdir "%BAZEL_OUTPUT_USER_ROOT%"

:: Build copybara using Bazel.
bazel "--output_user_root=%BAZEL_OUTPUT_USER_ROOT%" build //java/com/google/copybara:copybara_deploy.jar ^
    --java_runtime_version=21 ^
    --tool_java_runtime_version=21 ^
    --repo_contents_cache= ^
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
  echo if "%%HOME%%"=="" set "HOME=%%USERPROFILE%%"
  echo java -jar "%%CONDA_PREFIX%%\share\copybara\copybara_deploy.jar" %%*
) > "%PREFIX%\bin\copybara.bat"
if errorlevel 1 exit /b 1

:: Collect licenses from all dependencies.
powershell -NoProfile -ExecutionPolicy Bypass -File "%RECIPE_DIR%\collect_licenses.ps1"
if errorlevel 1 exit /b 1
