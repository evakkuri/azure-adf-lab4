# Deployment script for EdX Data Factory course, exercise 4

# Phase 1: Deploy data storages and computing resources

## Variable definitions
$rgName = "adflab4"
$location = "northeurope"
$phase1DeploymentName = "deploymentTest" + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')
$workFolder = $PSScriptRoot

$deploymentTemplate = "\adf-lab4-azuredeploy.json"
$deploymentParameters = "\adf-lab4-azuredeploy.parameters.json"

## Deployment parameters
$deploymentParams = @{
    "Name" = $phase1DeploymentName
    "ResourceGroupName" = $rgName
    "TemplateFile" = ($workFolder + $deploymentTemplate)
    "TemplateParameterFile" = ($workFolder + $deploymentParameters)
    "Mode" = "Complete"
    "Verbose" = $true
}

## Create resource group
New-AzureRmResourceGroup -Name $rgName -Location $location

## Run deployment script
New-AzureRmResourceGroupDeployment @deploymentParams

## Store outputs
$phase1Deployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $rgName -Name $phase1DeploymentName
$labStorageAccountName = $phase1Deployment.Outputs.storageAccountName.value
$labStorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $rgName -Name $labStorageAccountName).value[0]
$sqlServerName = $phase1Deployment.Outputs.sqlServerName.value
$sqlServerFullName = $phase1Deployment.Outputs.sqlServerName.value + ".database.windows.net"
$sqlDatabaseName = $phase1Deployment.Outputs.sqlDatabaseName.value

# Phase 2: Create blob container and upload source data to container 

## Create container into Storage account
$storageAccountContext = New-AzureStorageContext `
	-StorageAccountName $labStorageAccountName `
	-StorageAccountKey $labStorageAccountKey

Write-Host ("Creating Storage Container " + $containerName + " to Storage Account " + $saName) 

New-AzureStorageContainer `
	-Name $containerName `
	-Context $storageAccountContext

## Import function to upload to Blob
$uploadtoBlobFunctionScript = $workFolder + "\common-UploadFilestoBlob.ps1"
. $uploadtoBlobFunctionScript

## Arguments
$containerName = "adf-lab4"
$sourceDataFolderPath = Read-Host -Prompt 'Input the folder path for the data to upload'

## Run function - upload target files to Blob

Write-Host "Writing data files to Storage Container"

Upload-FileToAzureStorageContainer `
	-StorageAccountName $labStorageAccountName `
	-StorageAccountKey $labStorageAccountKey `
	-ContainerName $containerName `
	-sourceFileRootDirectory $sourceDataFolderPath `
	-Verbose

# Phase 3: Create receiving SQL table

## Import function to write to SQL Database
$sqlCommandFunctionScript = $workFolder + "\common-Invoke-SQLCommand.ps1"
. $sqlCommandFunctionScript

## Arguments
$keyVaultName = "eliascommonkeyvault"
$sqlServerLoginSecretName = "adflab4-sqllogin"
$sqlServerPasswordSecretName = "adflab4-sqlpassword"

$sqlCreateTableQuery = "CREATE TABLE dbo.usql_logs (log_date varchar(12), requests int, bytes_in float, bytes_out float);"
$sqlServerLogin = (Get-AzureKeyVaultSecret -VaultName $keyVaultName -Name $sqlServerLoginSecretName).SecretValueText
$sqlServerPassword = (Get-AzureKeyVaultSecret -VaultName $keyVaultName -Name $sqlServerPasswordSecretName).SecretValueText

## Run function to write table to SQL Database

#DEBUG - check that all variables have been declared
$sqlCreateTableQuery
$sqlServerFullName
$SqlDatabaseName
$sqlServerLogin
$sqlServerPassword
#/DEBUG

Write-Host "Creating table into SQL Database..."

Invoke-SqlCommand `
    -Server $sqlServerFullName `
    -Database $sqlDatabaseName `
    -Username $sqlServerLogin `
    -Password $sqlServerPassword `
    -Query $sqlCreateTableQuery

# Phase 4: Create Data Factory and contained resources - Linked Services, Datasets, Pipelines

## Variable definitions
$phase3DeploymentName = "deploymentTest" + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')
$phase3TemplateFile = $workFolder + "\adf-lab4-datafactorycomposed.json"
$phase3ParametersFile = $workFolder + "\adf-lab4-datafactorycomposed.parameters.json"
$dataLakeAnalyticsAccountName = $phase1Deployment.Outputs.dataLakeAnalyticsAccountName.value
$dataLakeStoreName = $phase1Deployment.Outputs.dataLakeStoreName.value

$labStorageAccountKeySecure = ConvertTo-SecureString -String $labStorageAccountKey -AsPlainText -Force

$phase3Params = @{
	"Name" = $phase3DeploymentName
	"ResourceGroupName" = $rgName
	"TemplateFile" = $phase3TemplateFile
	"TemplateParameterFile" = $phase3ParametersFile
	"Verbose" = $true
	"Mode" = "Incremental"
	"storageAccountName" = $labStorageAccountName
    "storageContainerName" = $containerName
	"storageAccountKey" = $labStorageAccountKeySecure
	"sqlServerName" = $sqlServerName
	"sqlDatabaseName" = $sqlDatabaseName
	"dataLakeAnalyticsAccountName" = $dataLakeAnalyticsAccountName
	"dataLakeStoreName" = $dataLakeStoreName
    "namePrefixLong" = 'adflab4-dev-neu-'	
}

## Deployment
New-AzureRmResourceGroupDeployment @phase3Params