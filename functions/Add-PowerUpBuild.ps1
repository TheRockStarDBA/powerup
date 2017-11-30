﻿
function Add-PowerUpBuild {
<#
	.SYNOPSIS
		Creates a new deployment package from specified set of scripts
	
	.DESCRIPTION
		Creates a new zip package which would contain a set of deployment scripts
	
	.PARAMETER ScriptPath
		A description of the ScriptPath parameter.
	
	.PARAMETER Name
		Output package name. Can be full file path or just a file name.
	
	.PARAMETER Build
		A description of the Build parameter.
	
	.PARAMETER ApplicationName
		A description of the ApplicationName parameter.
	
	.PARAMETER DeploymentMethod
		A description of the DeploymentMethod parameter.
	
	.PARAMETER UserName
		A description of the UserName parameter.
	
	.PARAMETER Password
		A description of the Password parameter.
	
	.PARAMETER ConnectionTimeout
		A description of the ConnectionTimeout parameter.
	
	.PARAMETER Encrypt
		A description of the Encrypt parameter.
	
	.PARAMETER Force
		A description of the Force parameter.
	
	.PARAMETER ConfigurationFile
		A description of the ConfigurationFile parameter.
	
	.PARAMETER Version
		A description of the Version parameter.
	
	.EXAMPLE
		PS C:\> New-PowerUpPackage -ScriptPath $value1 -Name 'Value2'
	
	.NOTES
		Additional information about the function.
#>
	[CmdletBinding(DefaultParameterSetName = 'Default',
				   SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   Position = 1)]
		[object[]]$ScriptPath,
		[Parameter(Mandatory = $false,
				   Position = 2)]
		[Alias('FileName', 'Name', 'Package')]
		[string]$Path,
		[Parameter(ParameterSetName = 'Default')]
		[string]$Build,
		[switch]$SkipValidation
	)
	
	begin {
		$currentDate = Get-Date
		if (!$Build) {
			$Build = [string]$currentDate.Year + '.' + [string]$currentDate.Month + '.' + [string]$currentDate.Day + '.' + [string]$currentDate.Hour
		}
		if (!(Test-Path $Path)) {
			throw "Package $Path not found. Aborting deployment."
			return
		}
		else {
			$pFile = Get-Item $Path
		}
		
		#Create new build object
		$currentBuild = [PowerUpBuild]::new($Build)
	}
	process {
		foreach ($scriptItem in $ScriptPath) {
			if (!(Test-Path $scriptItem)) {
				throw "The following path is not valid: $ScriptPath"
			}
			Write-Verbose "Processing path $scriptItem"
			Get-ChildScriptItem $scriptItem | ForEach-Object { $currentBuild.NewScript($_.FullName, $_.ReplacePath) }
		}
	}
	end {
		#Create a temp folder
		$workFolder = New-TempWorkspaceFolder
		
		#Extract package
		Write-Verbose "Extracting package $pFile to $workFolder"
		Expand-Archive -Path $pFile -DestinationPath $workFolder -Force:$Force
		
		#Validate package
		if (!$SkipValidation) {
			$validation = Test-PowerUpPackage -Path $workFolder -Unpacked
			if ($validation.IsValid -eq $false) {
				$throwMessage = "The following package items have failed validation: "
				$throwMessage += ($validation.ValidationTests | Where-Object { $_.Result -eq $false }).Item -join ", "
				throw $throwMessage
			}
		}
		
		#Load package object
		$PackageFile = Join-Path $workFolder "PowerUp.package.json"
		if (!(Test-Path $PackageFile)) {
			throw "Package file $PackageFile not found. Aborting."
		}
		else {
			$pFile = Get-Item $PackageFile
		}
		Write-Verbose "Loading package information from $pFile"
		$package = [PowerUpPackage]::FromFile($pFile.FullName)
		
		Write-Verbose "Adding $currentBuild to the package object"
		$package.AddBuild($currentBuild)
		
		if ($pscmdlet.ShouldProcess($package, "Adding files to the package")) {
			$scriptDir = Join-Path $workFolder $package.ScriptDirectory
			if (!(Test-Path $scriptDir)) {
				$null = New-Item $scriptDir -ItemType Directory
			}
			Copy-FilesToBuildFolder $currentBuild $scriptDir
			
			$packagePath = Join-Path $workFolder $package.PackageFile
			Write-Verbose "Writing package file $packagePath"
			$package.SaveToFile($packagePath, $true)
			
			Write-Verbose "Repackaging original package $Path"
			Compress-Archive "$workFolder\*" -DestinationPath $Path -Force
			
			Get-Item $Path
			
		}
		if ($workFolder.Name -like 'PowerUpWorkspace*') {
			Write-Verbose "Removing temporary folder $workFolder"
			Remove-Item $workFolder -Recurse -Force
		}
	}
}