# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
$ErrorActionPreference = 'SilentlyContinue'	# resume on error

$localDockerUsersMembers = Get-LocalGroupMember -Group "docker-users" 
if ($localDockerUsersMembers -and -not ($localDockerUsersMembers -like "NT AUTHORITY\Authenticated Users")) {
	Write-Host ">>> Adding 'Authenticated Users' to docker-users group ..."
	Add-LocalGroupMember -Group "docker-users" -Member "NT AUTHORITY\Authenticated Users"
}
