
function ConvertTo-Hashtable { 
    param ( 
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
        [object] $Object 
    );

    $output = @{}; 

    if ($Object) {
        $Object | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $output[$_] = $Object | Select-Object -ExpandProperty $_ }
    }

    return  $output;
}