
function rsync ($source,$target) {

  $sourceFiles = Get-ChildItem -Path $source -Recurse
  $targetFiles = Get-ChildItem -Path $target -Recurse

  if ($debug -eq $true) {
    Write-Output "Source=$source, Target=$target"
    Write-Output "sourcefiles = $sourceFiles TargetFiles = $targetFiles"
  }
  <#
  1=way sync, 2=2 way sync.
  #>
  $syncMode = 1

  if ($sourceFiles -eq $null -or $targetFiles -eq $null) {
    Write-Host "Empty Directory encountered. Skipping file Copy."
  } else
  {
    $diff = Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $targetFiles

    foreach ($f in $diff) {
      if ($f.SideIndicator -eq "<=") {
        $fullSourceObject = $f.InputObject.FullName
        $fullTargetObject = $f.InputObject.FullName.Replace($source,$target)

        Write-Host "Attempt to copy the following: " $fullSourceObject
        Copy-Item -Path $fullSourceObject -Destination $fullTargetObject
      }


      if ($f.SideIndicator -eq "=>" -and $syncMode -eq 2) {
        $fullSourceObject = $f.InputObject.FullName
        $fullTargetObject = $f.InputObject.FullName.Replace($target,$source)

        Write-Host "Attempt to copy the following: " $fullSourceObject
        Copy-Item -Path $fullSourceObject -Destination $fullTargetObject
      }

    }
  }
}
