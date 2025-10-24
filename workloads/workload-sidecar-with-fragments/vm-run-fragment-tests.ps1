cd C:\
tar -zxvf lcows_fragment.tar.gz
foreach ($d in @("lcow_primarya","lcow_primaryb","lcow_justsc")) {
    cd $d
    .\stop.ps1
    .\pull.ps1
    if (-not $?) {
        Write-Output "ERROR: ${d}: pull.ps1 failed"
        exit 1
    }
    .\runp.ps1
    if (-not $?) {
        Write-Output "ERROR: ${d}: runp.ps1 failed"
        exit 1
    }
    .\startc.ps1
    if (-not $?) {
        Write-Output "ERROR: ${d}: startc.ps1 failed"
        exit 1
    }
    cd ..
}

sleep 10

function Expect-Lcow-Output-Contains($dirName, $expectToHave) {
    cd C:\$dirName
    $output = cat container_log_*.log
    if ("$output" -notmatch "$expectToHave") {
        Write-Output "ERROR: ${dirName}: output.txt does not contain expected string: ${expectToHave}"
        Write-Output "Actual output:"
        cat container_log_*.log
        exit 1
    }
    cd C:\
}

Expect-Lcow-Output-Contains "lcow_primarya" "Hello from sidecar A"
Expect-Lcow-Output-Contains "lcow_primaryb" "Hello from sidecar B"
Expect-Lcow-Output-Contains "lcow_justsc" "Started server process"

echo "fragment: success"
