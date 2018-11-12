<#PSScriptInfo
.VERSION 1.0.0
.GUID 09cb0ae8-532b-4f8f-bbe0-2224f52b714a
.AUTHOR Microsoft Corporation
.COMPANYNAME Microsoft Corporation
.COPYRIGHT 2018 (c) Microsoft Corporation. All rights reserved.
.TAGS DSC,DesiredStateConfiguration
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS Deploy-DscGallerySamplesAsResourceModule,Import-DscGallerySamplesPrerequisitesModules,Merge-DscGallerySamplesToResourceModule
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
Version 1.0.0:  First published version.
#>

<#
    .SYNOPSIS
        Imports all dependent modules for composite resources.

    .DESCRIPTION
        Imports all dependent modules for all found DSC samples in PowerShell
        Gallery with the author 'Microsoft Corporation', and has the tag
        'DSCConfiguration'.

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

function Import-ScriptDependentModules
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
        [System.Collections.Specialized.OrderedDictionary[]]
        $Dependencies
    )

    # Get unique dependent modules.
    $uniqueModuleNames = $Dependencies.Name | Sort-Object -Unique

    foreach ($uniqueModuleName in $uniqueModuleNames)
    {
        # Get all dependent versions and sort them ascending.
        $uniqueModuleVersions = ($Dependencies | Where-Object -FilterScript { $_.Name -eq $uniqueModuleName }).MinimumVersion | Sort-Object -Unique

        foreach ($uniqueModuleVersion in $uniqueModuleVersions)
        {
            $moduleVersion = [Version] $uniqueModuleVersion

            # Convert revision to zero if it is not used.
            if ($moduleVersion.Revision -eq -1)
            {
                $moduleVersion = [Version]::New(
                    $moduleVersion.Major,
                    $moduleVersion.Minor,
                    $moduleVersion.Build,
                    0
                )
            }

            Write-Verbose -Message ('Importing dependent on module ''{0} (v{1})'' to automation account ''{2}''.' -f $uniqueModuleName, $moduleVersion, $AutomationAccountName) -Verbose

            $publishModuleToAutomationAccountParameters = @{
                ResourceGroupName     = $ResourceGroupName
                AutomationAccountName = $AutomationAccountName
                ModuleName            = $uniqueModuleName
                MaximumVersion        = $moduleVersion
            }

            Import-GalleryModuleToAutomationAccount @publishModuleToAutomationAccountParameters
        }
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

Write-Verbose -Message 'Finding all DSC sample scripts in PowerShell Gallery, to evaluate dependent modules. This can take a while.' -Verbose

$galleryScripts = Find-Script -Tag 'DSCConfiguration' | Where-Object -FilterScript {
    $_.Author -eq 'Microsoft Corporation'
}

if ($galleryScripts)
{
    $importCompositeDependentModulesParameters = $defaultParameters.Clone()
    $importCompositeDependentModulesParameters += @{
        Dependencies = $galleryScripts.Dependencies
    }

    Import-ScriptDependentModules @importCompositeDependentModulesParameters
}
else
{
    throw 'Could not find any scripts in the Gallery with the specified criteria.'
}
