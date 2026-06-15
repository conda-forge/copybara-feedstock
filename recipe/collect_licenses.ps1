$ErrorActionPreference = "Stop"

$srcDir = $env:SRC_DIR
$libraryLicensesDir = Join-Path $srcDir "library_licenses"
$collectorDir = Join-Path $srcDir "license-collector"

New-Item -ItemType Directory -Force -Path $libraryLicensesDir | Out-Null
New-Item -ItemType Directory -Force -Path $collectorDir | Out-Null
Set-Location $collectorDir

$moduleFile = Join-Path $srcDir "MODULE.bazel"
$moduleText = Get-Content -Raw -Path $moduleFile
$mavenDeps = @(
    [regex]::Matches($moduleText, '"([a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+)"') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)

$pomLines = New-Object System.Collections.Generic.List[string]
$pomLines.Add('<?xml version="1.0" encoding="UTF-8"?>')
$pomLines.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"')
$pomLines.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
$pomLines.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">')
$pomLines.Add('    <modelVersion>4.0.0</modelVersion>')
$pomLines.Add('    <groupId>com.google.copybara</groupId>')
$pomLines.Add('    <artifactId>license-collector</artifactId>')
$pomLines.Add('    <version>1.0.0</version>')
$pomLines.Add('    <packaging>pom</packaging>')
$pomLines.Add('    <dependencies>')

foreach ($dep in $mavenDeps) {
    $parts = $dep.Split(":")
    $pomLines.Add('        <dependency>')
    $pomLines.Add("            <groupId>$($parts[0])</groupId>")
    $pomLines.Add("            <artifactId>$($parts[1])</artifactId>")
    $pomLines.Add("            <version>$($parts[2])</version>")
    $pomLines.Add('        </dependency>')
}

$pomLines.Add('    </dependencies>')
$pomLines.Add('    <build>')
$pomLines.Add('        <plugins>')
$pomLines.Add('            <plugin>')
$pomLines.Add('                <groupId>org.codehaus.mojo</groupId>')
$pomLines.Add('                <artifactId>license-maven-plugin</artifactId>')
$pomLines.Add('                <version>2.7.1</version>')
$pomLines.Add('            </plugin>')
$pomLines.Add('        </plugins>')
$pomLines.Add('    </build>')
$pomLines.Add('</project>')

$pomFile = Join-Path $collectorDir "pom.xml"
[System.IO.File]::WriteAllLines($pomFile, $pomLines, [System.Text.UTF8Encoding]::new($false))

Write-Host "Generated pom.xml with $($mavenDeps.Count) Maven dependencies"

$mavenLicenseDir = Join-Path $libraryLicensesDir "maven"
$thirdPartyFile = Join-Path $libraryLicensesDir "THIRD-PARTY.xml"

mvn license:download-licenses `
    "-DlicensesOutputDirectory=$mavenLicenseDir" `
    "-DlicensesOutputFile=$thirdPartyFile" `
    "-DincludeTransitiveDependencies=true" `
    -q
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $srcDir

$bazelStartupArgs = @()
if ($env:BAZEL_OUTPUT_USER_ROOT) {
    $bazelStartupArgs += "--output_user_root=$env:BAZEL_OUTPUT_USER_ROOT"
}

$outputBase = (& bazel @bazelStartupArgs info output_base "--repo_contents_cache=")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$externalDir = Join-Path $outputBase "external"
if (Test-Path $externalDir) {
    Write-Host "Collecting licenses from Bazel external dependencies..."
    Get-ChildItem -Path $externalDir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like "LICENSE*" -or
            $_.Name -like "LICENCE*" -or
            $_.Name -like "NOTICE*" -or
            $_.Name -like "COPYING*"
        } |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($externalDir.Length).TrimStart("\", "/")
            $depName = ($relativePath -split "[\\/]", 2)[0]
            $destinationDir = Join-Path (Join-Path $libraryLicensesDir "bazel") $depName
            New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destinationDir $_.Name) -Force
        }
}

Get-ChildItem -Path $libraryLicensesDir -Directory -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1) } |
    Remove-Item -Force

$licenseFiles = @(
    Get-ChildItem -Path $libraryLicensesDir -File -Recurse -ErrorAction SilentlyContinue
)
Write-Host "License collection complete. Found $($licenseFiles.Count) license files."

& bazel @bazelStartupArgs shutdown
if ($LASTEXITCODE -ne 0) {
    Write-Host "Bazel shutdown failed with exit code $LASTEXITCODE; continuing with cleanup"
}

function Enable-WriteAccess {
    param([string] $Path)

    if (-not (Test-Path $Path)) {
        return
    }

    Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }

    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
}

Get-ChildItem -Path $srcDir -Force -Filter "bazel-*" -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            try {
                [System.IO.Directory]::Delete($_.FullName, $false)
            } catch {
                Write-Host "Could not remove Bazel workspace link $($_.FullName): $_"
            }
        } elseif ($_.PSIsContainer) {
            Enable-WriteAccess -Path $_.FullName
        }
    }

Enable-WriteAccess -Path $outputBase
