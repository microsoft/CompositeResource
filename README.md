# Composite Resource Module

[![Build status](https://ci.appveyor.com/api/projects/status/c80a8uja31avfha4/branch/master?svg=true)](https://ci.appveyor.com/project/mgreenegit/compositeresource/branch/master)

The purpose of this project is to provide a tool for converting
[PowerShell Desired State Configuration](https://docs.microsoft.com/en-us/powershell/dsc/overview)
[configurations](https://docs.microsoft.com/en-us/powershell/dsc/configurations)
to
[composite resources](https://docs.microsoft.com/en-us/powershell/dsc/authoringresourcecomposite).

The tool does not convert a *script file*, it converts a *configuration*. 
This way writing out to a temporary file is never required.

Usage:

```powershell
ConvertTo-CompositeResource -ConfigurationName 'Test' -Author 'Name' -Description 'Text'
```

or

```powershell
$configurationScript = @"
Configuration Example3
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    node localhost
    {
        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }
    }
}
"@

ConvertTo-CompositeResource -Script $configurationScript -Author 'Name' -Description 'Text'
```

Output:

    <no command output returned when successful>

By default the tool will write a new folder based on the configuration name + 'DSC',
e.g. 'TestDSC'.
The folder contains a version folder which then contains a module and manifest.
The module should be immediately functional once it is copied into a path present
in `$env:PSModulePath`.

To test if the resource is available, run the command:

```powershell
Get-DscResource
```

## Release Notes

09/07/2018 - Michael Greene and Johan Ljunggren collaborated on a minimum viable product for the
solution and published the result as an open source project on GitHub.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
