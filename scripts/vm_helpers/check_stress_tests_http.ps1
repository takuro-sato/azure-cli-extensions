try {
  Set-Alias -Name crictl -Value C:\ContainerPlat\crictl.exe
  Set-Alias -Name shimdiag -Value C:\ContainerPlat\shimdiag.exe

  (crictl pods -o json | convertfrom-json).items | foreach {
    $podId=$_.id
    $podName=$_.metadata.name
    $ip=(crictl inspectp $podId | ConvertFrom-Json).info.cniResult.Interfaces.eth0.IPConfigs.IP
    echo "Checking $podName - $ip"
    try {
      $res=Invoke-RestMethod -TimeoutSec 5 -Uri "http://${ip}:80/index.txt"
      if ($res.Trim() -ne "Hello") {
        Write-Output "ERROR: unexpected response: $res"
      }
    } catch {
      Write-Output "ERROR: failed to check HTTP on pod $podName" $_.Exception.ToString()
    }
  }
} catch {
  Write-Output "ERROR: failed to run check_http on pod $podName" $_.Exception.ToString()
}
