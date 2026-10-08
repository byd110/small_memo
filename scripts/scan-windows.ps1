# Inspect an existing download without executing any of its programs.
$ErrorActionPreference = 'Stop'
$report = Join-Path $PWD 'security-report'
$inputDirectory = Join-Path $PWD 'scan-input'
New-Item -ItemType Directory -Force -Path $report | Out-Null
Start-Transcript -Path (Join-Path $report 'defender-scan.txt')
try {
    $archive = Join-Path $inputDirectory 'windows.zip'
    if (!(Test-Path $archive -PathType Leaf)) { throw 'Input archive is missing' }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $inputDirectory 'bundle')
    $files = @(Get-ChildItem $inputDirectory -Recurse -File)
    if (!($files | Where-Object Name -eq 'small_memo.exe')) { throw 'App executable is missing' }
    $files | ForEach-Object {
        $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
        [PSCustomObject]@{
            File = [IO.Path]::GetRelativePath($inputDirectory, $_.FullName)
            Bytes = $_.Length
            SHA256 = $hash.Hash
        }
    } | Export-Csv -NoTypeInformation (Join-Path $report 'sha256.csv')
    $files | Where-Object Extension -in '.exe', '.dll' | ForEach-Object {
        $signature = Get-AuthenticodeSignature -LiteralPath $_.FullName
        [PSCustomObject]@{
            File = [IO.Path]::GetRelativePath($inputDirectory, $_.FullName)
            SignatureStatus = $signature.Status.ToString()
            Signer = $signature.SignerCertificate.Subject
        }
    } | Export-Csv -NoTypeInformation (Join-Path $report 'signatures.csv')

    Start-Service WinDefend
    Update-MpSignature
    $status = Get-MpComputerStatus
    $status | Select-Object AMServiceEnabled, AntivirusEnabled, AMEngineVersion,
        AntivirusSignatureVersion, AntivirusSignatureLastUpdated |
        ConvertTo-Json | Set-Content (Join-Path $report 'defender-version.json')
    if (!$status.AMServiceEnabled -or !$status.AntivirusEnabled) {
        throw 'Defender is not enabled; no clean-scan claim can be made'
    }
    $scanner = Get-ChildItem "$env:ProgramData\Microsoft\Windows Defender\Platform\*\MpCmdRun.exe" |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (!$scanner) { $scanner = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" }
    # With remediation disabled, exclusions are ignored and archive contents are
    # scanned. Detections remain in command output; never execute the input files.
    & $scanner -Scan -ScanType 3 -File $inputDirectory -DisableRemediation
    $scanExit = $LASTEXITCODE
    [PSCustomObject]@{ ExitCode = $scanExit; CompletedAt = (Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json | Set-Content (Join-Path $report 'scan-result.json')
    if ($scanExit -ne 0) { throw "Defender reported a detection or scan error (exit $scanExit); inspect the log" }
    # Catch unexpected quarantine/removal during extraction or hashing as well.
    foreach ($file in $files) {
        if (!(Test-Path -LiteralPath $file.FullName)) { throw "A scan input disappeared: $($file.Name)" }
    }
    'Defender completed without a detection. This is not proof of safety or a Chrome verdict.' |
        Tee-Object -FilePath (Join-Path $report 'summary.txt')
} finally {
    Stop-Transcript
}
