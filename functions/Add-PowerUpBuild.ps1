﻿
function Add-PowerUpBuild {
	<#
	.SYNOPSIS
		Creates a new build in existing PowerUp package
	
	.DESCRIPTION
		Creates a new build in existing PowerUp package from specified set of scripts.
	
	.PARAMETER ScriptPath
		A collection of script files to add to the build. Accepts Get-Item/Get-ChildItem objects and wildcards.
		Will recursively add all of the subfolders inside folders. See examples if you want only custom files to be added.
		During deployment, scripts will be following this deployment order:
		 - Item order provided in the ScriptPath parameter
		   - Files inside each child folder (both folders and files in alphabetical order)
			 - Files inside the root folder (in alphabetical order)
			 
		Aliases: SourcePath
	
	.PARAMETER Path
		Path to the existing PowerUpPackage.
		Aliases: Name, FileName, Package
	
	.PARAMETER Build
		A string that would be representing a build number of this particular build. 
		Optional - can be genarated automatically.
		Can only contain characters that will be valid on the filesystem.
	
	.PARAMETER SkipValidation
		Skip package validation step when attempting to add build to the package.
	
	.PARAMETER Type
		Adds only files that were not added to the package yet. The following options are available:
		* New: add new files based on their source path (can be relative)
		* Modified: adds files only if they have been modified since they had last been added to the package
		* Unique: adds unique files to the build based on their hash values. Compares hashes accross the whole package
		* All: add all files regardless of their previous involvement
		
		More than one value can be specified at the same time.
		
		Default value: All
	
	.PARAMETER UniqueOnly
		Out of all specified script files, only add new/modified files that have not been added to any of the package builds yet. 
		Compares file hash against all the file hashes from the existing builds to determine eligibility.
		Moving file into different folder will NOT make it a new file, as it would still have the same hash value.
	
	.PARAMETER Unpacked
		Intended for internal usage. Allows to work with unpacked package structures (basically, folders).
	
	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
		# Add new build 2.0 to the existing package using files from .\Scripts\2.0
		Add-PowerUpBuild -Path MyPackage.zip -ScriptPath .\Scripts\2.0 -Build 2.0

	.EXAMPLE
		# Add new build 2.1 to the existing package using modified files from .\Scripts\2.0
		Get-ChildItem .\Scripts\2.0 | Add-PowerUpBuild -Path MyPackage.zip -Build 2.1 -UniqueOnly

	.EXAMPLE
		# Add new build 3.0 to the existing package checking if there were any new files in the Scripts folder
		Add-PowerUpBuild -Path MyPackage.zip -ScriptPath .\Scripts\* -Build 3.0 -NewOnly

	.NOTES
		See 'Get-Help New-PowerUpPackage' for additional info about packages.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true,
			Position = 1)]
		[Alias('FileName', 'Name', 'Package')]
		[string]$Path,
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 2)]
		[Alias('SourcePath')]
		[object[]]$ScriptPath,
		[string]$Build,
		[switch]$SkipValidation,
		[ValidateSet('New', 'Modified', 'Unique', 'All')]
		[string[]]$Type = 'All'
	)
	
	begin {
		if (!$Build) {
			$Build = Get-NewBuildNumber
		}
		$scriptCollection = @()
		Write-Verbose "Loading package information from $pFile"
		$package = Get-PowerUpPackage -Path $Path
	}
	process {
		foreach ($scriptItem in $ScriptPath) {
			Write-Verbose "Processing path item $scriptItem"
			$scriptCollection += Get-ChildScriptItem $scriptItem
		}
	}
	end {
		#Prepare the scripts that's going to be added to the build
		$scriptsToAdd = @()
		foreach ($childScript in $scriptCollection) { 
			# Include file by default
			$includeFile = $Type -contains 'All'
			if ($Type -contains 'New') {
				#Check if the script path was already added in one of the previous builds
				if (!$package.SourcePathExists($childScript.SourcePath)) {
					$includeFile = $true
					Write-Verbose "File $($childScript.SourcePath) was not found among the package source files, adding to the list."
				}
			}
			if ($Type -contains 'Modified') {
				#Check if the file was modified in the previous build
				if ($package.ScriptModified($childScript.FullName, $childScript.SourcePath)) {
					$includeFile = $true
					Write-Verbose "Hash of the file $($childScript.FullName) was modified since last deployment, adding to the list."
				}
			}
			if ($Type -contains 'Unique') {
				#Check if the script hash was already added in one of the previous builds
				if (!$package.ScriptExists($childScript.FullName)) {
					$includeFile = $true
					Write-Verbose "Hash of the file $($childScript.FullName) was not found among the package scripts, adding to the list.."
				}
			}
			if ($includeFile) {
				$scriptsToAdd += $childScript
			}
			else {
				Write-Verbose "File $($childScript.FullName) was not added to the current build due to -Type restrictions: $($Type -join ',')"
			}
		}	

		if ($scriptsToAdd) {

			#Create new build object
			$currentBuild = $package.NewBuild($Build)

			foreach ($buildScript in $scriptsToAdd) {
				Write-Verbose "Adding file '$($buildScript.FullName)' to $currentBuild"
				$currentBuild.NewScript($buildScript) 
			}

			if ($pscmdlet.ShouldProcess($package, "Writing new build $currentBuild into the original package")) {
				$currentBuild.Alter()
			}
		}
		$package
	}
}