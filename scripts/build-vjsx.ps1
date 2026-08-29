param(
  [string]$Out = "",
  [string]$AppRunnerOut = "",
  [string]$QuickjsPath = "",
  [string]$QuickjsLibPath = "",
  [string]$Compiler = "",
  [string]$VFlags = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($Out)) {
  $Out = Join-Path $RepoRoot "bin\vjsx.exe"
}
if ([string]::IsNullOrWhiteSpace($AppRunnerOut)) {
  $appRunnerDir = Split-Path -Parent $Out
  if ([string]::IsNullOrWhiteSpace($appRunnerDir)) {
    $appRunnerDir = "."
  }
  $AppRunnerOut = Join-Path $appRunnerDir "vjsx-app-runner.exe"
}
if ([string]::IsNullOrWhiteSpace($QuickjsPath)) {
  $QuickjsPath = $env:VJS_QUICKJS_PATH
}
if ([string]::IsNullOrWhiteSpace($QuickjsLibPath)) {
  $QuickjsLibPath = $env:VJS_QUICKJS_LIB_PATH
}
if ([string]::IsNullOrWhiteSpace($VFlags)) {
  $VFlags = $env:VJS_V_FLAGS
}
if ([string]::IsNullOrWhiteSpace($Compiler)) {
  $Compiler = $env:VJS_V_CC
}
if ([string]::IsNullOrWhiteSpace($Compiler)) {
  $Compiler = "msvc"
}

if ([string]::IsNullOrWhiteSpace($QuickjsPath)) {
  $workRoot = if ([string]::IsNullOrWhiteSpace($env:VJS_QUICKJS_WORK_ROOT)) {
    $RepoRoot
  } else {
    $env:VJS_QUICKJS_WORK_ROOT
  }
  $env:VJS_QUICKJS_WORK_ROOT = $workRoot
  $ensureScript = Join-Path $RepoRoot "scripts\ensure-quickjs.sh"
  $QuickjsPath = (& bash $ensureScript).Trim()
  if ([string]::IsNullOrWhiteSpace($QuickjsPath)) {
    throw "failed to resolve QuickJS source path"
  }
}

$outDir = Split-Path -Parent $Out
if (![string]::IsNullOrWhiteSpace($outDir)) {
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
$appRunnerOutDir = Split-Path -Parent $AppRunnerOut
if (![string]::IsNullOrWhiteSpace($appRunnerOutDir)) {
  New-Item -ItemType Directory -Force -Path $appRunnerOutDir | Out-Null
}

$flagList = @()
if (![string]::IsNullOrWhiteSpace($VFlags)) {
  $flagList += $VFlags.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
}

$hasCompiler = $false
for ($i = 0; $i -lt $flagList.Count; $i++) {
  if ($flagList[$i] -eq "-cc" -or $flagList[$i].StartsWith("-cc=")) {
    $hasCompiler = $true
    break
  }
}
if (!$hasCompiler) {
  $flagList = @("-cc", $Compiler) + $flagList
}

function Test-VDefineFlag {
  param(
    [string[]]$Flags,
    [string]$Name
  )

  for ($i = 0; $i -lt $Flags.Count; $i++) {
    $flag = $Flags[$i]
    if ($flag -eq "-d" -and ($i + 1) -lt $Flags.Count -and $Flags[$i + 1] -eq $Name) {
      return $true
    }
    if ($flag -eq "-d=$Name" -or $flag -eq "-d$Name") {
      return $true
    }
  }
  return $false
}

function Resolve-QuickjsLib {
  param(
    [string]$SourcePath
  )

  if (![string]::IsNullOrWhiteSpace($script:QuickjsLibPath)) {
    return (Resolve-Path $script:QuickjsLibPath).Path
  }

  $tempRoot = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    [System.IO.Path]::GetTempPath()
  } else {
    $env:RUNNER_TEMP
  }
  $buildRoot = if ([string]::IsNullOrWhiteSpace($env:VJS_QUICKJS_BUILD_DIR)) {
    Join-Path $tempRoot "vjsx-quickjs-ng-build"
  } else {
    $env:VJS_QUICKJS_BUILD_DIR
  }

  if (Test-Path $buildRoot) {
    Remove-Item -Recurse -Force $buildRoot
  }
  & cmake -S $SourcePath -B $buildRoot -G Ninja -DCMAKE_BUILD_TYPE=Release -DQJS_BUILD_LIBC=ON -DBUILD_SHARED_LIBS=OFF 2>&1 |
    ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  & cmake --build $buildRoot --target qjs_exe 2>&1 |
    ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  $qjsLib = Get-ChildItem -Path $buildRoot -Filter qjs.lib -File -Recurse | Select-Object -First 1
  if ($null -eq $qjsLib) {
    throw "qjs.lib not found under $buildRoot"
  }
  $qjsExe = Get-ChildItem -Path $buildRoot -Filter qjs.exe -File -Recurse | Select-Object -First 1
  if ($null -ne $qjsExe) {
    $smokeOutput = (& $qjsExe.FullName -e "print(1 + 1)" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
    if ($smokeOutput -ne "2") {
      throw "quickjs-ng smoke expected 2, got: $smokeOutput"
    }
  }

  return $qjsLib.FullName
}

$hasBuildQuickjs = Test-VDefineFlag -Flags $flagList -Name "build_quickjs"
$hasLinkQuickjs = Test-VDefineFlag -Flags $flagList -Name "link_quickjs"
if (!$hasBuildQuickjs -and !$hasLinkQuickjs) {
  if ($Compiler -eq "msvc") {
    $flagList += @("-d", "link_quickjs")
    $hasLinkQuickjs = $true
  } else {
    $flagList += @("-d", "build_quickjs")
    $hasBuildQuickjs = $true
  }
}

Push-Location $RepoRoot
try {
  $env:VJS_QUICKJS_PATH = $QuickjsPath
  if ($hasLinkQuickjs) {
    $env:VJS_QUICKJS_LIB_PATH = Resolve-QuickjsLib -SourcePath $QuickjsPath
    Write-Host "VJS_QUICKJS_LIB_PATH=$env:VJS_QUICKJS_LIB_PATH"
  }
  & v @flagList -prod -o $Out .\cli_runner_bin
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  & v @flagList -prod -o $AppRunnerOut .\app_runner_bin
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  Write-Output $Out
} finally {
  Pop-Location
}
