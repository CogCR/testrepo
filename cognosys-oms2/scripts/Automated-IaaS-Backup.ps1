<#
.Synopsis
   Runbook for automated IaaS VM Backup in Azure using Backup and Site Recovery (OMS)
.DESCRIPTION
   This Runbook will enable Backup on existing Azure IaaS VMs.
   You need to provide input to the Resource Group name that contains the Backup and Site Recovery (OMS) Resourcem the name of the recovery vault, 
   Fabric type, preferred policy and the template URI where the ARM template is located. Have fun!
#>

$credential = Get-AutomationPSCredential -Name 'AzureCredentials'
$subscriptionId = Get-AutomationVariable -Name 'AzureSubscriptionID'
$OMSWorkspaceId = Get-AutomationVariable -Name 'OMSWorkspaceId'
$OMSWorkspaceKey = Get-AutomationVariable -Name 'OMSWorkspaceKey'
$OMSWorkspaceName = Get-AutomationVariable -Name 'OMSWorkspaceName'
$OMSResourceGroupName = Get-AutomationVariable -Name 'OMSResourceGroupName'
$TemplateUri='https://raw.githubusercontent.com/krnese/AzureDeploy/master/OMS/MSOMS/AzureIaaSBackup/azuredeploy.json'
$OMSRecoveryVault = Get-AutomationVariable -Name 'OMSRecoveryVault'

$ErrorActionPreference = 'Stop'

Try {
        Login-AzureRmAccount -credential $credential
        Select-AzureRmSubscription -SubscriptionId $subscriptionId

    }

Catch {
        $ErrorMessage = 'Login to Azure failed.'
        $ErrorMessage += " `n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
      }

Try {

        $Location = Get-AzureRmRecoveryServicesVault -Name $OMSRecoveryVault -ResourceGroupName $OMSResourceGroupName | select -ExpandProperty Location
    }

Catch {
        $ErrorMessage = 'Failed to retrieve the OMS Recovery Location property'
        $ErrorMessage += "`n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
      }

Try {
        $VMs = Get-AzureRmVM | Where-Object {$_.Location -eq $Location}
    }

Catch {
        $ErrorMessage = 'Failed to retrieve the VMs.'
        $ErrorMessage += "`n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
      }

# Enable Backup

Try {
        Foreach ($vm in $vms)
        {
            New-AzureRmResourceGroupDeployment -Name $vm.name `
                                               -ResourceGroupName $OMSResourceGroupName `
                                               -TemplateUri $TemplateUri `
                                               -omsRecoveryResourceGroupName $OMSResourceGroupName `
                                               -vmResourceGroupName $vm.ResourceGroupName `
                                               -vaultName $OMSRecoveryVault `
                                               -vmName $vm.name `
                                               -Verbose
        }
    }

Catch {
        $ErrorMessage = 'Failed to enable backup using ARM template.'
        $ErrorMessage += "`n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
      }
      
      
      
      
      # new code for security
      
      
      
      Try {
       #region update PS

Install-Module -Name PowerShellGet -Force
Install-Module -Name AzureRM.Security -AllowPrerelease
Install-Module -Name  AzureRm.OperationalInsights
#endregion update PS

#region List all ASC PowerShell commands
Get-Command -Module AzureRm.Security
#endregion

#region Azure Microsoft.Security ResourceProvider registration
#Verify registration
Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Security | Select-Object ProviderNamespace, Locations, RegistrationState

#Register the Microsoft.Security resource provider
Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Security
#endregion

#region Assign ASC Azure Policy
#Assign the ASC Azure Policies to a subscription
$mySub = Get-AzureRmSubscription -SubscriptionID $subscriptionId #-SubscriptionName "<mySubscriptionName>"
$subscription = "/subscriptions/$mySub"
$policySetDefinition = Get-AzureRmPolicySetDefinition | Where-Object {$_.Properties.DisplayName -eq "[Preview]: Enable Monitoring in Azure Security Center"}
New-AzureRmPolicyAssignment -PolicySetDefinition $policySetDefinition -Name $OMSWorkspaceName"assigname" -Scope $subscription -PolicyParameter "{}"

#Assign the ASC Azure Policies to a resource group
New-AzureRmResourceGroup -Name $OMSResourceGroupName -Location  $Location
$resourceGroup = Get-AzureRmResourceGroup -Name $OMSResourceGroupName
$policySetDefinition = Get-AzureRmPolicySetDefinition | Where-Object {$_.Properties.DisplayName -eq "[Preview]: Enable Monitoring in Azure Security Center"}
New-AzureRmPolicyAssignment -PolicySetDefinition $policySetDefinition -Name $OMSWorkspaceName"assigname" -Scope $resourceGroup.ResourceId -PolicyParameter "{}"
#endregion

#region GET Autoprovision settings for subscriptions
#Get Autoprovision setting for the current scope
Get-AzureRmSecurityAutoProvisioningSetting

#Get the Autoprovision setting for all Azure subscriptions 
Get-AzureRmContext -ListAvailable -PipelineVariable myAzureSubs | Set-AzureRmContext | ForEach-Object{
    Write-Output $myAzureSubs
    Get-AzureRmSecurityAutoProvisioningSetting | Select-Object AutoProvision
    "-"*100
}


# get subs from all and enable for all

$subscriptions = Get-AzureRmSubscription

foreach($subNameFromFile in $subscriptions.Id){

try{
#  Write-Output "/subscriptions/$subNameFromFile"
  $subsidforscope= "/subscriptions/$subNameFromFile"

$workspaceObj = Get-AzureRmOperationalInsightsWorkspace -Name $OMSWorkspaceName -ResourceGroupName $OMSResourceGroupName
Set-AzureRmSecurityWorkspaceSetting -Name default -WorkspaceId $workspaceObj.ResourceId -Scope $subsidforscope




}catch
    {
    $ErrorMessage = 'subscription loop error'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction ignore
    }
}
# get subs from all and enable for all



#endregion

#region SET AutoProvision settings
#Set AutoProvision to ON for the current scope
Set-AzureRmSecurityAutoProvisioningSetting -Name "default" -EnableAutoProvision

#Set AutoProvision to ON for all subscriptions
Get-AzureRmContext -ListAvailable -PipelineVariable myAzureSubs | Set-AzureRmContext | ForEach-Object{
    Set-AzureRmSecurityAutoProvisioningSetting -Name "default" -EnableAutoProvision
}


#endregion

#region Azure Security Pricing
#Get current pricing tier
Get-AzureRmSecurityPricing | Select-Object Name, PricingTier

#Set Azure Security Center pricing tier for the default scope, use either "Standard" or "Free"
Set-AzureRmSecurityPricing -Name default -PricingTier "Standard"

#region Security Alerts
#Tip: you can filter out fields of interest by using Select-Object
Get-AzureRmSecurityAlert
Get-AzureRmSecurityAlert | Select-Object AlertDisplayName, CompromisedEntity, Description
#endregion




    }

Catch {
        $ErrorMessage = 'Security Center errors'
        $ErrorMessage += "`n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction ignore
      }




