<#PSScriptInfo
.VERSION 1.0.0
.GUID f4960ac8-5bb9-4698-9ffa-5361c70d2cf1
.AUTHOR Microsoft Corporation
.COMPANYNAME Microsoft Corporation
.COPYRIGHT 2018 (c) Microsoft Corporation. All rights reserved.
.TAGS DSC,DesiredStateConfiguration
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS Deploy-DscGallerySamplesAsResourceModule,Import-DscGallerySamplesCompositeResourceDependentModules,Merge-DscGallerySamplesToResourceModule
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
Version 1.0.0:  First published version.
#>

<#
    .SYNOPSIS
        Imports all prerequisites modules that is needed to compose the composite
        module.

    .DESCRIPTION
        Imports all prerequisites modules that is needed to compose the composite
        module.

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
    $AutomationAccountName
)

function Import-GalleryModuleToAutomationAccount
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ModuleName,

        [Parameter()]
        [Version]
        $MaximumVersion
    )

    $baseContentLinkUrl = 'https://www.powershellgallery.com/api/v2/package'

    $defaultParameters = @{
        ResourceGroupName     = $ResourceGroupName
        AutomationAccountName = $AutomationAccountName
    }

    $getAzureRmAutomationModuleParameters = $defaultParameters.Clone()
    $getAzureRmAutomationModuleParameters['Name'] = $ModuleName

    $module = Get-AzureRmAutomationModule @getAzureRmAutomationModuleParameters -ErrorAction 'SilentlyContinue'
    if (-not $module -or ($module -and $PSBoundParameters.ContainsKey('MaximumVersion')))
    {
        $contentLinkUri = ('{0}/{1}' -f $baseContentLinkUrl, $ModuleName)

        if ($PSBoundParameters.ContainsKey('MaximumVersion'))
        {
            if ($module -and $module.Version -gt $MaximumVersion)
            {
                throw ('The module ''{0}'' in the automation account ''{1}'' has version ''{2}'', and is newer then the required version ''{3}''.' -f $ModuleName, $AutomationAccountName, $module.Version, $MaximumVersion)
            }

            if ($module -and $module.Version -eq $MaximumVersion)
            {
                Write-Verbose -Message ('The module ''{0}'' in the automation account ''{1}'' already have the correct version ''{2}''.' -f $ModuleName, $AutomationAccountName, $module.Version) -Verbose
                return
            }

            # Suffixing correct version number to the content link.
            $contentLinkUri = ('{0}/{1}' -f $contentLinkUri, $MaximumVersion)
        }

        Write-Verbose -Message ('Importing module ''{0}'' to automation account ''{1}'' from content link ''{2}''.' -f $ModuleName, $AutomationAccountName, $ContentLinkUri) -Verbose

        $newAzureRmAutomationModuleParameters = $defaultParameters.Clone()
        $newAzureRmAutomationModuleParameters += @{
            ContentLinkUri = $contentLinkUri
            Name           = $ModuleName
        }

        New-AzureRmAutomationModule @newAzureRmAutomationModuleParameters | Out-Null

        $timeoutCounter = 0

        do
        {
            $timeoutCounter++

            if ($timeoutCounter -eq 5)
            {
                Write-Verbose -Message ('Waiting for import of module ''{0}'' to automation account ''{1}'' to finish.' -f $ModuleName, $AutomationAccountName) -Verbose
            }

            Start-Sleep -Seconds 40

            $compositeResourceModule = Get-AzureRmAutomationModule @getAzureRmAutomationModuleParameters
        } until ($compositeResourceModule.ProvisioningState -eq 'Succeeded' -or $timeoutCounter -gt 10)

        if ($timeoutCounter -gt 10)
        {
            throw 'The module ''{0}'' was not deployed within the timeout period.' -f $ModuleName
        }
    }
    else
    {
        Write-Verbose -Message ('The module ''{0}'' already exist in the automation account ''{1}''.' -f $ModuleName, $AutomationAccountName) -Verbose
    }
}

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

$publishModuleToAutomationAccountParameters = $defaultParameters.Clone()
$publishModuleToAutomationAccountParameters += @{
    ModuleName = 'CompositeResource'
}

Import-GalleryModuleToAutomationAccount @publishModuleToAutomationAccountParameters

$publishModuleToAutomationAccountParameters = $defaultParameters.Clone()
$publishModuleToAutomationAccountParameters += @{
    ModuleName = 'PackageManagement'
}

Import-GalleryModuleToAutomationAccount @publishModuleToAutomationAccountParameters

$publishModuleToAutomationAccountParameters = $defaultParameters.Clone()
$publishModuleToAutomationAccountParameters += @{
    ModuleName = 'PowerShellGet'
}

Import-GalleryModuleToAutomationAccount @publishModuleToAutomationAccountParameters
