param([Parameter(Mandatory=$true)][string]$Subnet)
1..254 | ForEach-Object {
  $ip = "$Subnet.$_"
  if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
    [PSCustomObject]@{ IP = $ip; Status = "Online" }
  }
}
