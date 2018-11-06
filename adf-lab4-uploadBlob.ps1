# Phase 2: Upload blobs, create receiving SQL table

# Script parameters
Param (

    [string] [parameter (Mandatory = $true)] $ResourceGroupName,
    [string] [parameter (Mandatory = $true)] $StorageAccountName,
	[string] [parameter (Mandatory = $true)] $StorageAccountKey,
    [string] [parameter (Mandatory = $true)] $SqlServerName,
    [string] [parameter (Mandatory = $true)] $SqlDatabaseName,
    [string] [parameter (Mandatory = $true)] $KeyVaultName,
    [string] [parameter (Mandatory = $true)] $SqlServerLoginSecretName,
    [string] [parameter (Mandatory = $true)] $SqlServerPasswordSecretName,
    [string] [parameter (Mandatory = $true)] $sourceDataFolderPath

)

Write-Host $ResourceGroupName
Write-Host $StorageAccountName

## Create storage container for source data and U-SQL script

### Get keys to Storage Account
#$saName = (Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName).Outputs.storageAccountName.value

Write-Host ("Fetching Storage Account keys...")

#$saName = $StorageAccountName

#$saKeys = Get-AzureRmStorageAccountKey `
#			-ResourceGroupName $ResourceGroupName `
#			-Name $saName

#DEBUG
#Write-Host $saKeys
#/DEBUG

### Create container into Storage account
$storageAccountContext = New-AzureStorageContext `
	-StorageAccountName $StorageAccountName `
	-StorageAccountKey $StorageAccountKey

$containerName = "adf-lab4"

Write-Host ("Creating Storage Container " + $containerName + " to Storage Account " + $saName) 

New-AzureStorageContainer `
	-Name $containerName `
	-Context $storageAccountContext

## Upload source data & scripts to Blob Storage using function

function Upload-FileToAzureStorageContainer {
    [cmdletbinding()]
    param(
        $StorageAccountName,
        $StorageAccountKey,
        $ContainerName,
        $sourceFileRootDirectory,
        $Force
    )

    $ctx = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    $container = Get-AzureStorageContainer -Name $ContainerName -Context $ctx

    $container.CloudBlobContainer.Uri.AbsoluteUri
    if ($container) {
        $filesToUpload = Get-ChildItem $sourceFileRootDirectory -Recurse -File

        foreach ($x in $filesToUpload) {
            $targetPath = ($x.fullname.Substring($sourceFileRootDirectory.Length + 1)).Replace("\", "/")

            Write-Verbose "Uploading $("\" + $x.fullname.Substring($sourceFileRootDirectory.Length + 1)) to $($container.CloudBlobContainer.Uri.AbsoluteUri + "/" + $targetPath)"
            Set-AzureStorageBlobContent -File $x.fullname -Container $container.Name -Blob $targetPath -Context $ctx -Force:$Force | Out-Null
        }
    }
} 

Write-Host "Writing data files to Storage Container"

Upload-FileToAzureStorageContainer `
	-StorageAccountName $storageAccountName `
	-StorageAccountKey $storageAccountKey `
	-ContainerName $containerName `
	-sourceFileRootDirectory $sourceDataFolderPath `
	-Verbose

## Create target table to SQL Server

$sqlCreateTableQuery = "CREATE TABLE dbo.usql_logs (log_date varchar(12), requests int, bytes_in float, bytes_out float);"
$sqlServerLogin = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SqlServerLoginSecretName).SecretValueText
$sqlServerPassword = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SqlServerPasswordSecretName).SecretValueText

#DEBUG
$sqlCreateTableQuery
$SqlServerName
$SqlDatabaseName
$sqlServerLogin
$sqlServerPassword
#/DEBUG

## Function to invoke SQL command from Powershell

<#
.SYNOPSIS
    Performs a SQL query and returns an array of PSObjects.
.NOTES
    Author: Jourdan Templeton - hello@jourdant.me
.LINK 
    https://blog.jourdant.me/post/simple-sql-in-powershell
#>

function Invoke-SqlCommand() {
    [cmdletbinding(DefaultParameterSetName="integrated")]Param (
        [Parameter(Mandatory=$true)][Alias("Serverinstance")][string]$Server,
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$true, ParameterSetName="not_integrated")][string]$Username,
        [Parameter(Mandatory=$true, ParameterSetName="not_integrated")][string]$Password,
        [Parameter(Mandatory=$false, ParameterSetName="integrated")][switch]$UseWindowsAuthentication = $true,
        [Parameter(Mandatory=$true)][string]$Query,
        [Parameter(Mandatory=$false)][int]$CommandTimeout=0
    )
    
    #build connection string
    $connstring = "Server=$Server; Database=$Database; "
    If ($PSCmdlet.ParameterSetName -eq "not_integrated") { $connstring += "User ID=$username; Password=$password;" }
    ElseIf ($PSCmdlet.ParameterSetName -eq "integrated") { $connstring += "Trusted_Connection=Yes; Integrated Security=SSPI;" }
    
    #DEBUG
    Write-Host ("Connection string: " + $connstring)
    #/DEBUG

    #connect to database
    $connection = New-Object System.Data.SqlClient.SqlConnection($connstring)
    $connection.Open()
    
    #build query object
    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    $command.CommandTimeout = $CommandTimeout
    
    #run query
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataset) | out-null
    
    #return the first collection of results or an empty array
    If ($dataset.Tables[0] -ne $null) {$table = $dataset.Tables[0]}
    ElseIf ($table.Rows.Count -eq 0) { $table = New-Object System.Collections.ArrayList }
    
    $connection.Close()

    Write-Host "SQL command executed and connection to database closed"

    return $table
}

## Create table to database

Write-Host "Creating table into SQL Database..."

Invoke-SqlCommand `
    -Server $sqlServerName `
    -Database $sqlDatabaseName `
    -Username $sqlServerLogin `
    -Password $sqlServerPassword `
    -Query $sqlCreateTableQuery

Write-Host "Phase 2 script completed"