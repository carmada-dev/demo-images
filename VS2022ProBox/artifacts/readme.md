# Image specific artifacts

Files and directory inside of this folder are copied to the Packer VM before any package of pre/post script is executed.
Please be careful with large files. Communication to the Packer VM is using WinRM which is not a high speed tool when it comes to copying files (especially larger ones). [more](https://developer.hashicorp.com/packer/docs/provisioners/file#slowness-when-transferring-large-files-over-winrm)

## Large size artifacts

In case you need to upload large files to the Packer VM please rely on the resolve artifacts feature of this build pipeline. Instead of placing a large artifact file in this folder use a Windows shortcut, pointing to the download URL of the file. The name of the Windows shortcut file (plus the default extension '.url' for Windows shortcuts) must contain the name of the file after downloading.

```
largefile.zip.url --> [download] --> largefile.zip 
```

Resolving these shortcut files will happen after the artifacts upload.

## Downloading secrets for KeyVault

The same approach used for large size artifacts can be used to download sensitive files stored within a Azure KeyVault as BASE64 encoded secret. Use the secret identifier as the target URL of the Windows shortcut file.

