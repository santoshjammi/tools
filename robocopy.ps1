param ($configFile)

$config = Import-Csv $configFile
$logDir = "C:\Users\adm_mkande\robologs\"

Write-Output $configFile

foreach ($line in $config)
{
 $source = $($line.SourceFolder)
 $dest = $($line.DestFolder)
 #$source = $($line.split(",")[0])
 #$dest = $($line.split(",")[1])
 Write-Output $source $dest
 $logfile =  $logDir 
 $logfile += Split-Path $source -Leaf
 $logfile += $((get-date).ToLocalTime()).ToString("yyyyMMddHHmmss")
 $logfile += ".log"
 
 Add-Content $logfile "Backups start at $(Get-Date)"
 robocopy $source $dest /E  /R:0 /W:0 /LOG:$logfile
 Add-Content $logfile "Backups complete at $(Get-Date)"


 Get-ChildItem -Path $Folder1Path -Recurse | Where-Object {

    [string] $toDiff = $_.FullName.Replace($Folder1path, $Folder2path)
    # Determine what's in 2, but not 1
    [bool] $isDiff = (Test-Path -Path $toDiff) -eq $false

    if ($isDiff) {
        # Create a destination path that contains a folder structure
        $dest = $_.FullName.Replace($Folder1path, $Folder2path)
        Copy-Item -Path $_.FullName -Destination $dest -Verbose -Force
    }
}

}
