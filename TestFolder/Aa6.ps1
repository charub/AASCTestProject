param(
 [Parameter(Mandatory=$True)]
 [string]
 $siteidvalue,
 [Parameter(Mandatory=$True)]
 [string]
 $originsname,
 [Parameter(Mandatory=$False)]
 [string]
 $CustomDomainName,
 [Parameter(Mandatory=$False)]
 [string]
 $endpointrecreate
 )  
 

Disable-AzContextAutosave -Scope Process

$connection = Get-AutomationConnection -Name AzureRunAsConnection
Connect-AzAccount -ServicePrincipal -Tenant $connection.TenantID `
-ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint

$AzureContext = Set-AzContext -SubscriptionId $connection.SubscriptionID

$locationvalue = "West US"
$skuvaluename = "Premium_Verizon"
$ResourceGroupName = (Get-AzAutomationAccount | Where-Object {$_.AutomationAccountName -Like "NVAautomation-*"}).ResourceGroupName
$Env = (((Get-AzAutomationAccount | Where-Object {$_.AutomationAccountName -Like "NVAautomation-*"}).AutomationAccountName).split("NVAautomation-", 15)).Split('',[System.StringSplitOptions]::RemoveEmptyEntries)
$Env = $Env.tolower()
Write-Output $Env
$endpointNamevalue = "$Env-nva-cdn-site-$siteidvalue"
$profileNamesuffix = "$Env-nva-cdn-profile"
$tags = @{"siteId" = "$siteidvalue"}

$count=1

while($count -le 25)
{
	$profileNamevalue="$profileNamesuffix$count"
    $cdnProfile = Get-AzCdnProfile -ProfileName $profileNamevalue -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if($cdnProfile -eq $null) 
    {
        Write-Output "Profile Missing $profileNamevalue hence creating." 
        $cdnProfile = New-AzCdnProfile -ProfileName $profileNamevalue -ResourceGroupName $ResourceGroupName -Sku $skuvaluename -Location $locationvalue
    } else 
    {
       Write-Output "Profile already exist" 
    }
	
    $endpointcount = (Get-AzCdnEndpoint -ProfileName $profileNamevalue -ResourceGroupName $ResourceGroupName).Name  | Measure-Object
    if($endpointcount.count -lt 25)
    {
    $profileNamevalue="$profileNamesuffix$count"
    Write-Output $profileNamevalue
	break
    } elseif($endpointcount.count -ge 25) 
    {
    Write-Output "Endpoint limit exceeded" 
	$count++
	}	
}
  


$checkavailability = Get-AzCdnEndpointNameAvailability -EndpointName $endpointNamevalue

If($checkavailability.NameAvailable) { 
       Write-Output "Yes, Endpoint name is available." 
} elseif($checkavailability.NameAvailable -ne $null -And $endpointrecreate -eq "Yes")  { 
       Write-Output "No, Endpoint name is not available but need to be recreated"
} else {
       Write-Output "No, Endpoint name is not available."
	   exit
}





$cdnEndpoint= Get-AzCdnEndpoint -EndpointName $endpointNamevalue -CdnProfile $cdnProfile -ErrorAction SilentlyContinue

if($cdnEndpoint -eq $null) {
        Write-Output "Endpoint Missing hence creating." 
        $cdnEndpoint = New-AzCdnEndpoint -EndpointName $endpointNamevalue -CdnProfile $cdnProfile -OriginName $endpointNamevalue.tolower() -OriginHostName $originsname -Tag $tags
} elseif($cdnEndpoint -ne $null -And $endpointrecreate -eq "Yes") {	
        Write-Output "Endpoint is getting recreated" 
        Remove-AzCdnEndpoint -CdnEndpoint $cdnEndpoint -Force
        Start-Sleep 300
        $cdnEndpoint = New-AzCdnEndpoint -EndpointName $endpointNamevalue -CdnProfile $cdnProfile  -OriginName $endpointNamevalue.tolower() -OriginHostName $originsname -Tag $tags
} else {
       Write-Output("Endpoint already exist")
}



if ($CustomDomainName -eq $null -Or $cdnEndpoint -eq $null) {
       Write-Output "No CustomDomainName Added or endpoint missing"
	   exit
} else {
       Write-Output "Adding CustomDomainName" 
	   New-AzCdnCustomDomain -HostName $CustomDomainName -CustomDomainName $endpointNamevalue -EndpointName $endpointNamevalue -ProfileName $profileNamevalue -ResourceGroupName $ResourceGroupName
	   Enable-AzCdnCustomDomainHttps -ResourceGroupName $resourceGroupName -ProfileName $profileNamevalue -EndpointName $endpointNamevalue -CustomDomainName $endpointNamevalue      
}
