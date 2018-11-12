<#PSScriptInfo
.VERSION 1.0.0
.GUID 274982f6-7b5d-4c57-b58b-faaddda16601
.AUTHOR Microsoft Corporation
.COMPANYNAME Microsoft Corporation
.COPYRIGHT 2018 (c) Microsoft Corporation. All rights reserved.
.TAGS DSC,DesiredStateConfiguration
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS Import-DscGallerySamplesCompositeResourceDependentModules,Import-DscGallerySamplesPrerequisitesModules,Merge-DscGallerySamplesToResourceModule
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
Version 1.0.0:  First published version.
#>

<#
    .SYNOPSIS
        Deploys all DSC samples as a composite resource module.

    .DESCRIPTION
        Converts all found DSC samples in PowerShell Gallery, authored by
        'Microsoft Corporation' and has the tag 'DSCConfiguration', to
        individual composite resources into a resource module which is deployed
        to Azure Automation, together with the necessary dependent modules.

    .PARAMETER Subscription
        The subscription in which the automation account exist. This should be
        the subscription name or subscription id.

    .PARAMETER ResourceGroupName
        The name of the resource group in which the automation account exist.

    .PARAMETER AutomationAccountName
        The name of the automation to which to deploy the resource module and
        dependent modules.
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $Subscription,

    [Parameter(Mandatory = $true)]
    [System.String]
    $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [System.String]
    $AutomationAccountName,

    [Parameter()]
    [System.String]
    $ModuleName = 'CompositeModuleDsc',

    [Parameter()]
    [System.String]
    $ModuleVersion = '1.0.0',

    [Parameter(Mandatory = $true)]
    [System.Boolean]
    $AcceptLicense
)

$azureRunAsConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'

$connectAzureRmAccountParameters = @{
    ServicePrincipal      = $true
    Tenant                = $azureRunAsConnection.TenantID
    ApplicationID         = $azureRunAsConnection.ApplicationID
    CertificateThumbprint = $azureRunAsConnection.CertificateThumbprint
    Subscription          = $Subscription
}

Write-Verbose -Message 'Connecting to Azure subscription.' -Verbose

Connect-AzureRmAccount @connectAzureRmAccountParameters | Out-Null

$defaultParameters = @{
    ResourceGroupName     = $ResourceGroupName
    AutomationAccountName = $AutomationAccountName
}

Write-Verbose -Message 'Starting runbook Import-DscGallerySamplesPrerequisitesModules.' -Verbose

$runbookParameters = $defaultParameters.Clone()
$runbookParameters += @{
    Subscription = $Subscription
}

$startAzureRmAutomationRunbookParameters = $defaultParameters.Clone()
$startAzureRmAutomationRunbookParameters += @{
    Name       = 'Import-DscGallerySamplesPrerequisitesModules'
    Wait       = $true
    Parameters = $runbookParameters
}

Start-AzureRmAutomationRunbook @startAzureRmAutomationRunbookParameters

Write-Verbose -Message 'Starting runbook Import-DscGallerySamplesCompositeResourceDependentModules.' -Verbose

$runbookParameters = $defaultParameters.Clone()
$runbookParameters += @{
    Subscription = $Subscription
}

$startAzureRmAutomationRunbookParameters = $defaultParameters.Clone()
$startAzureRmAutomationRunbookParameters += @{
    Name       = 'Import-DscGallerySamplesCompositeResourceDependentModules'
    Wait       = $true
    Parameters = $runbookParameters
}

Start-AzureRmAutomationRunbook @startAzureRmAutomationRunbookParameters

Write-Verbose -Message 'Starting runbook Merge-DscGallerySamplesToResourceModule.' -Verbose

$runbookParameters = $defaultParameters.Clone()
$runbookParameters += @{
    Subscription  = $Subscription
    ModuleName    = $ModuleName
    ModuleVersion = $ModuleVersion
    AcceptLicense = $AcceptLicense
}
$startAzureRmAutomationRunbookParameters = $defaultParameters.Clone()
$startAzureRmAutomationRunbookParameters += @{
    Name       = 'Merge-DscGallerySamplesToResourceModule'
    Wait       = $true
    Parameters = $runbookParameters
}

Start-AzureRmAutomationRunbook @startAzureRmAutomationRunbookParameters

Write-Verbose -Message 'Runbook completed.' -Verbose
