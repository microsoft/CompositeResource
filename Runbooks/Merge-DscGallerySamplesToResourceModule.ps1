<#PSScriptInfo
.VERSION 1.0.0
.GUID c9ce444b-9d19-4743-b674-6f15f86cade7
.AUTHOR Microsoft Corporation
.COMPANYNAME Microsoft Corporation
.COPYRIGHT 2018 (c) Microsoft Corporation. All rights reserved.
.TAGS DSC,DesiredStateConfiguration
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS Deploy-DscGallerySamplesAsResourceModule,Import-CompositeResourceDependentModules,Import-PrerequisitesModules
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
Version 1.0.0:  First published version.
#>

<#
    .SYNOPSIS
        Merges all DSC samples as individual composite resources in a common resource module.

    .DESCRIPTION
        Merges all found DSC samples in PowerShell Gallery, authored by
        'Microsoft Corporation' and has the tag 'DSCConfiguration', as
        individual composite resources into a common resource module.
        THe resource module is deployed to Azure Automation, together with the
        necessary dependent modules.

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

Connect-AzureRmAccount @connectAzureRmAccountParameters

Write-Verbose -Message 'Finding and saving all DSC sample scripts in PowerShell Gallery. This can take a while.' -Verbose

$galleryScripts = Find-Script -Tag 'DSCConfiguration' | Where-Object -FilterScript {
    $_.Author -eq 'Microsoft Corporation'
}

if ($galleryScripts)
{
    $galleryScripts | Save-Script -Path '.\Scripts' -Force -AcceptLicense:$AcceptLicense

    $sampleConfigurations = Get-ChildItem -Path '.\Scripts\*' -Filter '*.ps1'
    foreach ($sampleConfiguration in $sampleConfigurations)
    {
        $scriptName = (Split-Path -Path $sampleConfiguration.FullName -Leaf)
        Write-Verbose -Message ('Converting script: {0}' -f $scriptName) -Verbose

        $script = Get-Content -Path $sampleConfiguration.FullName -Raw

        $convertToCompositeResourceParameters = @{
            Script        = $script
            ModuleName    = $ModuleName
            ModuleVersion = $ModuleVersion
            OutputPath    = '.\Module'
        }

        ConvertTo-CompositeResource @convertToCompositeResourceParameters
    }

    $archiveSourcePath = Join-Path -Path (Join-Path -Path '.\Module' -ChildPath $ModuleName) -ChildPath $ModuleVersion
    $archiveDestinationPath = Join-Path -Path '.' -ChildPath "$ModuleName.zip"

    Write-Verbose -Message 'Compressing module into a archive.' -Verbose
    Compress-Archive -Path $archiveSourcePath -DestinationPath $archiveDestinationPath -Force

    # Use the first 24 chars of a guid (after it is stripped of dashes).
    $storageAccountName = ((New-Guid) -replace '-').Substring(1, 24)
    $storageAccountLocation = (Get-AzureRmResourceGroup -ResourceGroupName $ResourceGroupName).Location

    try
    {
        Write-Verbose -Message ('Creating temporary storage account ''{0}'' in the location ''{1}'', inside the resource group ''{2}'', for temporary storage of the module archive.' -f $storageAccountName, $storageAccountLocation, $ResourceGroupName) -Verbose

        $newAzureRmStorageAccountParameters = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $storageAccountName
            Location          = $storageAccountLocation
            SkuName           = 'Standard_LRS'
            Kind              = 'BlobStorage'
            AccessTier        = 'Hot'
        }

        $newAzureRmStorageAccountResult = New-AzureRmStorageAccount @newAzureRmStorageAccountParameters

        $storageContainerName = 'tempmoduleupload'

        Write-Verbose -Message ('Creating storage container ''{0}'' in the storage account ''{1}''.' -f $storageContainerName, $storageAccountName) -Verbose

        $newAzureStorageContainerParameters = @{
            Name       = $storageContainerName
            Context    = $newAzureRmStorageAccountResult.Context
            Permission = 'Blob'
        }

        $newAzureStorageContainerResult = New-AzureStorageContainer @newAzureStorageContainerParameters

        Write-Verbose -Message ('Uploading module archive ''{0}'' to storage container ''{1}'' in the storage account ''{2}''.' -f $archiveDestinationPath, $storageContainerName, $storageAccountName) -Verbose

        $setAzureStorageBlobContentParameters = @{
            Context   = $newAzureRmStorageAccountResult.Context
            Container = $storageContainerName
            File      = $archiveDestinationPath
            Blob      = "$ModuleName.zip"
            Force     = $true
        }

        $blobObject = Set-AzureStorageBlobContent @setAzureStorageBlobContentParameters

        Write-Verbose -Message ('Importing composite module ''{0}'' into automation account ''{1}'' from storage container URI ''{2}''.' -f $ModuleName, $AutomationAccountName, $blobObject.ICloudBlob.Uri.AbsoluteUri) -Verbose

        $newAzureRmAutomationModuleParameters = @{
            ResourceGroupName     = $ResourceGroupName
            AutomationAccountName = $AutomationAccountName
            Name                  = $ModuleName
            ContentLinkUri        = $blobObject.ICloudBlob.Uri.AbsoluteUri
        }

        New-AzureRmAutomationModule @newAzureRmAutomationModuleParameters | Out-Null

        $getAzureRmAutomationModuleParameters = @{
            ResourceGroupName     = $ResourceGroupName
            AutomationAccountName = $AutomationAccountName
            Name                  = $ModuleName
        }

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
        else
        {
            Write-Verbose -Message ('Composite module ''{0}'' was successfully imported into automation account ''{1}''.' -f $ModuleName, $AutomationAccountName) -Verbose
        }
    }
    catch
    {
        throw $_
    }
    finally
    {
        $getAzureRmStorageAccountResult = Get-AzureRmStorageAccount -Name $storageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction 'SilentlyContinue'
        if ($getAzureRmStorageAccountResult)
        {
            Write-Verbose -Message ('Removing temporary storage account ''{0}'' , from the resource group ''{1}''.' -f $storageAccountName, $ResourceGroupName) -Verbose
            $getAzureRmStorageAccountResult | Remove-AzureRmStorageAccount -Force
        }
    }
}
else
{
    throw 'Could not find any scripts in the Gallery with the specified criteria.'
}
