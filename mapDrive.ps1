$mapUser=$env:BUILDER_USER
$mapPassword=$env:BUILDER_PWD
$sharedPath=$env:SHARE_DIR

$PWord=$mapPassword|ConvertTo-SecureString -AsPlainText -Force
 
$myCreds=New-Object System.Management.Automation.PsCredential($mapUser,$PWord)
echo "myCreds is "$myCreds
 
New-PSDrive -Name "I" -Scope Global -PSProvider "FileSystem" -Root $sharedPath -Credential $myCreds
