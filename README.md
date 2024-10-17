# Microsoft DevBox Custom Images Demo Repository

This repository contains examples and CI/CD pipelines to build custom images for Microsoft DevBox.

## Structure

[Images](#-images)
- [image.json](#imagejson)
    - [DevDrive](#devdrive)
- [Image specific artifacts](#image-specific-artifacts)
  - [Large size artifacts](#large-size-artifacts)
  - [Downloading secrets for KeyVault](#downloading-secrets-for-keyvault)

[Packer](#packer)

[CI/CD Pipelines](#cicd-pipelines)
- [GitHub Actions](#github-actions)
- [Azure DevOps Pipelines](#azure-devops-pipelines)

[Config](#config)  
[Factory](#factory)  
[Schemas](#schemas)  
[Scripts](#scripts)  
[Templates](#templates)  
[Artifacts](#artifacts)  
[Local Development & Build](#local-development--build)


## 📷 Images

Every folder named xxxBox represents a custom image for Microsoft DevBox. The folder contains the following files:

### image.json

The `image.json` file is the main configuration file for the image. [Here](./TemplateBox/image.json) you can find an example or template for the `image.json` file.

#### DevDrive

A DevDrive can be mounted into a DevBox. It uses not NTFS but ReFS to improve performance. [click for more information](https://devblogs.microsoft.com/visualstudio/devdrive/)

### Image specific artifacts

Files and directory inside of this folder are copied to the Packer VM before any package of pre/post script is executed.
Please be careful with large files. Communication to the Packer VM is using WinRM which is not a high speed tool when it comes to copying files (especially larger ones). [more](https://developer.hashicorp.com/packer/docs/provisioners/file#slowness-when-transferring-large-files-over-winrm)

#### Large size artifacts

In case you need to upload large files to the Packer VM please rely on the resolve artifacts feature of this build pipeline. Instead of placing a large artifact file in this folder use a Windows shortcut, pointing to the download URL of the file. The name of the Windows shortcut file (plus the default extension '.url' for Windows shortcuts) must contain the name of the file after downloading.

```
largefile.zip.url --> [download] --> largefile.zip
```

Resolving these shortcut files will happen after the artifacts upload.

#### Downloading secrets for KeyVault

The same approach used for large size artifacts can be used to download sensitive files stored within a Azure KeyVault as BASE64 encoded secret. Use the secret identifier as the target URL of the Windows shortcut file.

## Packer

## CI/CD Pipelines
### GitHub Actions
### Azure DevOps Pipelines

## Config

## Factory

## Schemas
In [_schemas](./_schemas/) you can find the JSON schema files for the image.json, aliases, defaults, factory and general definitions.

## Scripts

## Templates

## Artifacts
In [_artifacts](./_artifacts/) you can find a `devbox.bgi`. A `.bgi` (BgInfo Configuration File) file keeps track of computer configuration information and stores custom settings chosen by the user

## Local Development & Build



