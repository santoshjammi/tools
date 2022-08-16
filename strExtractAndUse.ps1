Param([String]$path)
$newVariable = Split-Path $path -Leaf

#write-output $newVariable
#_SN needs to be in a string and extraction is done for a pattern
if($newVariable.Contains("_SN"))
{
$test1 = $newVariable.Split('_')[1]

#Write-Output $test1
$test1=$test1.split('.')[0].Substring(2)

Write-Output $test1
#$env.SERIAL_FROM_PATH=$test1
[System.Environment]::SetEnvironmentVariable('SERIAL_FROM_PATH', $test1)
}
else
{
Write-Output "Serial number not embedded"
#$env.SERIAL_FROM_PATH="Serial number not embedded"
[System.Environment]::SetEnvironmentVariable('SERIAL_FROM_PATH', 'Serial number not embedded')
}
