param(
  [Parameter()][string]$additionalChecksScript = "",
  [Parameter()][int]$checkInterval = 30,
  [Parameter()][bool]$doExecChecks = $true,
  [Parameter()][string]$uploadLogsTo = ""
)
Set-Alias -Name crictl -Value C:\ContainerPlat\crictl.exe
Set-Alias -Name shimdiag -Value C:\ContainerPlat\shimdiag.exe

$logsFolder = "C:\check_logs"
if (Test-Path -Path $logsFolder) {
  Remove-Item -Path $logsFolder -Recurse -Force
}
New-Item -Path $logsFolder -ItemType Directory | Out-Null

$checkLogFile = Join-Path $logsFolder "check_loop.log"
$terminatedFlagFile = Join-Path $logsFolder "all_terminated"
$timestampFile = Join-Path $logsFolder "last_updated_timestamp"

function DoUploadFiles {
  if ($uploadLogsTo) {
    Get-Date -Format "o" > $timestampFile
    $files = Get-ChildItem -Path $logsFolder -Recurse
    foreach ($file in $files) {
      if ($file.PSIsContainer) {
        continue
      }
      $name = $file.FullName.Substring($logsFolder.Length + 1).Replace("\", "/")
      $uri = "$uploadLogsTo/$name"
      $filePath = $file.FullName
      C:\storage_put.ps1 -Uri $uri -InFile $filePath *> "C:\upload_logs.log"
      if ($LASTEXITCODE -ne 0) {
        echo "WARNING: Failed to upload $filePath to $uri" >> $checkLogFile
        cat "C:\upload_logs.log" >> $checkLogFile
      }
    }
  }
}

while ((crictl ps -q).Length) {
  try {
    $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    echo "Starting check at $time" >> $checkLogFile

    $lcow_dirs = (Get-Item C:\lcow* |% { $_.Name })
    if (!$lcow_dirs) {
      echo "ERROR: No lcow* found in C:\" >> $checkLogFile
      exit 1
    }

    if ($doExecChecks) {
      foreach ($lcow_dir_name in $lcow_dirs) {
        $LASTEXITCODE=0
        & "C:\$lcow_dir_name\check.ps1" *>> $checkLogFile
        if ($LASTEXITCODE -ne 0) {
          echo "ERROR: C:\$lcow_dir_name\check.ps1 exited with code $LASTEXITCODE" >> $checkLogFile
        } else {
          echo "Checked $lcow_dir_name" >> $checkLogFile
        }
      }
    }

    cd C:\vm_helpers
    if ($additionalChecksScript) {
      $LASTEXITCODE=0
      & ".\$additionalChecksScript" *>> $checkLogFile
      if ($LASTEXITCODE -ne 0) {
        echo "ERROR: $additionalChecksScript exited with code $LASTEXITCODE" >> $checkLogFile
      }
    }

    foreach ($lcow_dir_name in $lcow_dirs) {
      if (!(Test-Path -Path $logsFolder\$lcow_dir_name)) {
        New-Item -Path $logsFolder\$lcow_dir_name -ItemType Directory | Out-Null
      }
      cp C:\$lcow_dir_name\*.log $logsFolder\$lcow_dir_name -Force
    }

    DoUploadFiles

    sleep $checkInterval
  } catch {
    echo "ERROR: $_" >> $checkLogFile
    continue
  }
}

echo "------ All containers terminated ------" >> $checkLogFile
echo "" > $terminatedFlagFile
DoUploadFiles
