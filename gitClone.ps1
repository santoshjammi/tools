Param([String]$url)

$user=$env:user
$git_token=$env:token

$results=$url.Split("\/\/")
$final_url=$results[0]+"//"+$user+":"+$git_token+"@"+$results[1]+$results[2]+"/"+$results[3]+"/"+$results[4]
Write-Output $final_url
git clone $final_url
