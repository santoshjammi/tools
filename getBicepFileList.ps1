param($diretoryPath="D:\projects\yamini\bicep\azure-docs-bicep-samples\samples")

$results = @()
$bicepFileList="bicepFileList.csv"
Get-ChildItem -Path $directoryPath -File -Recurse |
Where-Object {$_.Extension -eq '.bicep' } |
Foreach-Object {
    
    $details = @{            
        Directory             = $_.DirectoryName              
        name                  = $_.Name                 
        fullPath              = $_.FullName 
}
$results += New-Object PSObject -Property $details  
}
$results | export-csv -Path $bicepFileList -NoTypeInformation
