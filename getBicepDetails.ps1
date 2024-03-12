param($diretoryPath="D:\projects\yamini\bicep\azure-docs-bicep-samples\samples")

$results = @()
$bicepFileList="bicepFileList.csv"
Get-ChildItem -Path $diretoryPath -File -Recurse |
Where-Object {$_.Extension -eq '.bicep' } |
Foreach-Object {
    
    $details = @{            
        Directory             = $_.DirectoryName              
        name                  = $_.Name                 
        fullPath              = $_.FullName 
}
$results += New-Object PSObject -Property $details  

    	$FileContents = Get-Content -path $_.FullName
        $bicepFileName = "params/"+$_.Name.Split(".")[0]+".csv"
        Write-Output($bicepFileName)
        $fileName=$_.Name.Split(".")[0]
        $bicepFileParamResult=@()
        # $i=0; $i -le 10; $i++)
        For ($i=0; $i -le $FileContents.Length; $i++) {
            # Write-Output($FileContents[$i])
                if (($FileContents[$i]) -and ($FileContents[$i].StartsWith("@description")))
                {
                    $line=$FileContents[$i]
                    $nextLine=$FileContents[$i+1]
                    if($nextLine.StartsWith("param") -and $nextLine.split(" ")[1] -and $nextLine.split(" ")[2]){
                        # Write-Output($nextLine.split(" ")[1])
                        $bicepParamDetails=@{
                            fileName=$fileName
                            description=$line.split("@description")[1]
                            parameterName=$nextLine.split(" ")[1]
                            paramterType=$nextLine.split(" ")[2]
                        }
                        $bicepFileParamResult += New-Object PSObject -Property $bicepParamDetails  
                }
                        # Write-Output $line, $nextLine
                }
        }
        $bicepFileParamResult | export-csv -Path $bicepFileName -NoTypeInformation
    # Write-Output($_.FullName+","+$_.Name)
}
$results | export-csv -Path $bicepFileList -NoTypeInformation
