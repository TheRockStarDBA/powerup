Param (
	[switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
	# Is not a part of the global batch => import module
	#Explicitly import the module for testing
	Import-Module "$here\..\PowerUp.psd1" -Force
}
else {
	# Is a part of a batch, output some eye-catching happiness
	Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\PowerUpHelper.class.ps1"
. "$here\..\internal\classes\PowerUp.class.ps1"
. "$here\..\internal\functions\Get-ArchiveItem.ps1"
$packageName = "$here\etc\$commandName.zip"
$script:pkg = $script:build = $script:file = $null
$script1 = "$here\etc\install-tests\success\1.sql"
$script2 = "$here\etc\install-tests\success\2.sql"
$script3 = "$here\etc\install-tests\success\3.sql"

Describe "PowerUpPackage class tests" -Tag $commandName, UnitTests, PowerUpPackage {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "validating PowerUpPackage creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpPackage object" {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.ScriptDirectory | Should Be 'content'
			$script:pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
			$script:pkg.DeployFile.GetContent() | Should BeLike '*Invoke-PowerUpDeployment @params*'
			$script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$script:pkg.FileName | Should BeNullOrEmpty
			$script:pkg.$Version | Should BeNullOrEmpty
		}
		It "should save package to file" {
			{ $script:pkg.SaveToFile($packageName, $true) } | Should Not Throw
		}
		$results = Get-ArchiveItem $packageName
		It "should contain module files" {
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
		}
		It "should contain config files" {
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
		}
		It "should contain deploy file" {
			'Deploy.ps1' | Should BeIn $results.Path
		}
	}
	Context "validate PowerUpPackage being loaded from file" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
		It "should load package from file" {
			$script:pkg = [PowerUpPackage]::new($packageName)
			$script:pkg.ScriptDirectory | Should Be 'content'
			$script:pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
			$script:pkg.DeployFile.GetContent() | Should BeLike '*Invoke-PowerUpDeployment @params*'
			$script:pkg.ConfigurationFile.ToString() | Should Be 'PowerUp.config.json'
			($script:pkg.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$script:pkg.FileName | Should Be $packageName
			$script:pkg.$Version | Should BeNullOrEmpty
			$script:pkg.PackagePath | Should BeNullOrEmpty
		}
	}
	Context "should validate PowerUpPackage methods" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
		It "Should test GetBuilds method" {
			$script:pkg.GetBuilds() | Should Be $null
		}
		It "Should test NewBuild method" {
			$b = $script:pkg.NewBuild('1.0')
			$b.Build | Should Be '1.0'
			$b.PackagePath | Should Be '1.0'
			$b.Parent.GetType().Name | Should Be 'PowerUpPackage'
			$b.Scripts | Should BeNullOrEmpty
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
			$script:pkg.Version | Should Be '1.0'
		}
		It "Should test GetBuild method" {
			$b = $script:pkg.GetBuild('1.0')
			$b.Build | Should Be '1.0'
			$b.PackagePath | Should Be '1.0'
			$b.Parent.GetType().Name | Should Be 'PowerUpPackage'
			$b.Scripts | Should BeNullOrEmpty
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
		}
		It "Should test AddBuild method" {
			$script:pkg.AddBuild('2.0')
			$b = $script:pkg.GetBuild('2.0')
			$b.Build | Should Be '2.0'
			$b.PackagePath | Should Be '2.0'
			$b.Parent.GetType().Name | Should Be 'PowerUpPackage'
			$b.Scripts | Should BeNullOrEmpty
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
			$script:pkg.Version | Should Be '2.0'
		}
		It "Should test EnumBuilds method" {
			$script:pkg.EnumBuilds() | Should Be @('1.0', '2.0')
		}
		It "Should test GetVersion method" {
			$script:pkg.GetVersion() | Should Be '2.0'
		}
		It "Should test RemoveBuild method" {
			$script:pkg.RemoveBuild('2.0')
			'2.0' | Should Not BeIn $script:pkg.EnumBuilds()
			$script:pkg.GetBuild('2.0') | Should BeNullOrEmpty
			$script:pkg.Version | Should Be '1.0'
			#Testing overloads
			$b = $script:pkg.NewBuild('2.0')
			'2.0' | Should BeIn $script:pkg.EnumBuilds()
			$script:pkg.Version | Should Be '2.0'
			$script:pkg.RemoveBuild($b)
			'2.0' | Should Not BeIn $script:pkg.EnumBuilds()
			$script:pkg.GetBuild('2.0') | Should BeNullOrEmpty
			$script:pkg.Version | Should Be '1.0'
		}
		It "should test ScriptExists method" {
			$b = $script:pkg.GetBuild('1.0')
			$s = "$here\etc\install-tests\success\1.sql"
			$f = [PowerUpScriptFile]::new(@{SourcePath = $s; PackagePath = 'success\1.sql'})
			$f.SetContent([PowerUpHelper]::GetBinaryFile($s))
			$b.AddFile($f, 'Scripts')
			$script:pkg.ScriptExists($s) | Should Be $true
            $script:pkg.ScriptExists("$here\etc\install-tests\transactional-failure\1.sql") | Should Be $false
            { $script:pkg.ScriptExists("Nonexisting\path") } | Should Throw
		}
		It "should test ScriptModified method" {
			$s1 = "$here\etc\install-tests\success\1.sql"
			$s2 = "$here\etc\install-tests\success\2.sql"
			$script:pkg.ScriptModified($s2, $s1) | Should Be $true
			$script:pkg.ScriptModified($s1, $s1) | Should Be $false
		}
		It "should test SourcePathExists method" {
			$s1 = "$here\etc\install-tests\success\1.sql"
			$s2 = "$here\etc\install-tests\success\2.sql"
			$script:pkg.SourcePathExists($s1) | Should Be $true
			$script:pkg.SourcePathExists($s2) | Should Be $false
		}
		It "should test ExportToJson method" {
			$j = $script:pkg.ExportToJson() | ConvertFrom-Json
			$j.Builds | Should Not BeNullOrEmpty
			$j.ConfigurationFile | Should Not BeNullOrEmpty
			$j.DeployFile | Should Not BeNullOrEmpty
			$j.ScriptDirectory | Should Not BeNullOrEmpty
		}
		It "Should test GetPackagePath method" {
			$script:pkg.GetPackagePath() | Should Be 'content'
		}
		It "Should test RefreshModuleVersion method" {
			$script:pkg.RefreshModuleVersion()
			$script:pkg.ModuleVersion | Should Be (Get-Module PowerUp).Version
		}
		It "Should test RefreshFileProperties method" {
			$script:pkg.RefreshFileProperties()
			$FileObject = Get-Item $packageName
			$script:pkg.PSPath | Should Be $FileObject.PSPath.ToString()
			$script:pkg.PSParentPath | Should Be $FileObject.PSParentPath.ToString()
			$script:pkg.PSChildName | Should Be $FileObject.PSChildName.ToString()
			$script:pkg.PSDrive | Should Be $FileObject.PSDrive.ToString()
			$script:pkg.PSIsContainer | Should Be $FileObject.PSIsContainer
			$script:pkg.Mode | Should Be $FileObject.Mode
			$script:pkg.BaseName | Should Be $FileObject.BaseName
			$script:pkg.Name | Should Be $FileObject.Name
			$script:pkg.Length | Should Be $FileObject.Length
			$script:pkg.DirectoryName | Should Be $FileObject.DirectoryName
			$script:pkg.Directory | Should Be $FileObject.Directory.ToString()
			$script:pkg.IsReadOnly | Should Be $FileObject.IsReadOnly
			$script:pkg.Exists | Should Be $FileObject.Exists
			$script:pkg.FullName | Should Be $FileObject.FullName
			$script:pkg.Extension | Should Be $FileObject.Extension
			$script:pkg.CreationTime | Should Be $FileObject.CreationTime
			$script:pkg.CreationTimeUtc | Should Be $FileObject.CreationTimeUtc
			$script:pkg.LastAccessTime | Should Be $FileObject.LastAccessTime
			$script:pkg.LastAccessTimeUtc | Should Be $FileObject.LastAccessTimeUtc
			$script:pkg.LastWriteTime | Should Be $FileObject.LastWriteTime
			$script:pkg.LastWriteTimeUtc | Should Be $FileObject.LastWriteTimeUtc
			$script:pkg.Attributes | Should Be $FileObject.Attributes
		}

		It "Should test SetConfiguration method" {
			$config = @{ SchemaVersionTable = 'dbo.NewTable' } | ConvertTo-Json -Depth 1
			{ $script:pkg.SetConfiguration([PowerUpConfig]::new($config)) } | Should Not Throw
			$script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.NewTable'
		}
		$oldResults = Get-ArchiveItem $packageName | Where-Object IsFolder -eq $false
		#Sleep 1 second to ensure that modification date is changed
		Start-Sleep -Seconds 2
		It "should test Save*/Alter methods" {
			{ $script:pkg.SaveToFile($packageName) } | Should Throw #File already exists
			{ $script:pkg.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
			'content\1.0\success\1.sql' | Should BeIn $results.Path
		}
		# Testing file contents to be updated by the Save method
		$results = Get-ArchiveItem $packageName | Where-Object IsFolder -eq $false
		$saveTestsErrors = 0
		foreach ($result in $oldResults) {
			if ($result.LastWriteTime -ge ($results | Where-Object Path -eq $result.Path).LastWriteTime) {
				It "Should have updated Modified date for file $($result.Path)" {
					$result.LastWriteTime -lt ($results | Where-Object Path -eq $result.Path).LastWriteTime | Should Be $true
				}
				$saveTestsErrors++
			}
		}
		if ($saveTestsErrors -eq 0) {
			It "Ran silently $($oldResults.Length) file modification tests" {
				$saveTestsErrors | Should be 0
			}
		}
	}
}

Describe "PowerUpPackageFile class tests" -Tag $commandName, UnitTests, PowerUpPackage, PowerUpPackageFile {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "validate PowerUpPackageFile being loaded from file" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
			if (Test-Path "$here\etc\LoadFromFile") { Remove-Item "$here\etc\LoadFromFile" -Recurse}
		}
		BeforeAll {
			$p = [PowerUpPackage]::new()
			$b1 = $p.NewBuild('1.0')
			$s1 = $b1.NewScript($script1, 1)
			$b2 = $p.NewBuild('2.0')
			$s1 = $b2.NewScript($script2, 1)
			$p.SaveToFile($packageName)
			$null = New-Item "$here\etc\LoadFromFile" -ItemType Directory
			Expand-Archive $p.FullName "$here\etc\LoadFromFile"
		}
		It "should load package from file" {
			$p = [PowerUpPackageFile]::new("$here\etc\LoadFromFile\PowerUp.package.json")
			$p.ScriptDirectory | Should Be 'content'
			$p.DeployFile.ToString() | Should Be 'Deploy.ps1'
			$p.DeployFile.GetContent() | Should BeLike '*Invoke-PowerUpDeployment @params*'
			$p.ConfigurationFile.ToString() | Should Be 'PowerUp.config.json'
			($p.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$p.Configuration.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$p.FileName | Should Be "$here\etc\LoadFromFile"
			$p.PackagePath | Should Be "$here\etc\LoadFromFile"
			$p.$Version | Should BeNullOrEmpty
			$p.Builds.Build | Should Be @('1.0', '2.0')
			$p.Builds.Scripts | Should Be @('success\1.sql', 'success\2.sql')
		}
		It "should override Save/Alter methods" {
			$p = [PowerUpPackageFile]::new("$here\etc\LoadFromFile\PowerUp.package.json")
			{ $p.Save() } | Should Throw
			{ $p.Alter() } | Should Throw
		}
		It "should still save the package using SaveToFile method" {
			$p = [PowerUpPackageFile]::new("$here\etc\LoadFromFile\PowerUp.package.json")
			$p.SaveToFile($packageName, $true)
			$results = Get-ArchiveItem $packageName
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
			'content\1.0\success\1.sql' | Should BeIn $results.Path
			'content\2.0\success\2.sql' | Should BeIn $results.Path
		}
		It "Should test RefreshFileProperties method" {
			$p = [PowerUpPackageFile]::new("$here\etc\LoadFromFile\PowerUp.package.json")
			$p.RefreshFileProperties()
			$FileObject = Get-Item "$here\etc\LoadFromFile"
			$p.PSPath | Should Be $FileObject.PSPath.ToString()
			$p.PSParentPath | Should Be $FileObject.PSParentPath.ToString()
			$p.PSChildName | Should Be $FileObject.PSChildName.ToString()
			$p.PSDrive | Should Be $FileObject.PSDrive.ToString()
			$p.PSIsContainer | Should Be $FileObject.PSIsContainer
			$p.Mode | Should Be $FileObject.Mode
			$p.BaseName | Should Be $FileObject.BaseName
			$p.Name | Should Be $FileObject.Name
			$p.Length | Should Be $FileObject.Length
			$p.Exists | Should Be $FileObject.Exists
			$p.FullName | Should Be $FileObject.FullName
			$p.Extension | Should Be $FileObject.Extension
			$p.CreationTime | Should Be $FileObject.CreationTime
			$p.CreationTimeUtc | Should Be $FileObject.CreationTimeUtc
			$p.LastAccessTime | Should Be $FileObject.LastAccessTime
			$p.LastAccessTimeUtc | Should Be $FileObject.LastAccessTimeUtc
			$p.LastWriteTime | Should Be $FileObject.LastWriteTime
			$p.LastWriteTimeUtc | Should Be $FileObject.LastWriteTimeUtc
			$p.Attributes | Should Be $FileObject.Attributes
		}
	}

}

Describe "PowerUpBuild class tests" -Tag $commandName, UnitTests, PowerUpBuild {
	Context "tests PowerUpBuild object creation" {
		It "Should create new PowerUpBuild object" {
			$b = [PowerUpBuild]::new('1.0')
			$b.Build | Should Be '1.0'
			$b.PackagePath | Should Be '1.0'
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
		}
		It "Should create new PowerUpBuild object using custom object" {
			$obj = @{
				Build       = '2.0'
				PackagePath = '2.00'
				CreatedDate = (Get-Date).Date
			}
			$b = [PowerUpBuild]::new($obj)
			$b.Build | Should Be $obj.Build
			$b.PackagePath | Should Be $obj.PackagePath
			$b.CreatedDate | Should Be $obj.CreatedDate
		}
    }
    Context "tests PowerUpBuild file adding methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
		BeforeEach {
			if ( $script:pkg.GetBuild('1.0')) { $script:pkg.RemoveBuild('1.0') }
			$b = $script:pkg.NewBuild('1.0')
			# $f = [PowerUpFile]::new($script1, 'success\1.sql')
			# $b.AddScript($f)
			$script:build = $b
		}
		It "should test NewScript([psobject]) method" {
			$so = $script:build.NewScript(@{FullName = $script1; Depth = 1})
			#test build to contain the script
			'1.sql' | Should BeIn $script:build.Scripts.Name
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			#test the file returned to have all the necessary properties
			$so.SourcePath | Should Be $script1
			$so.PackagePath | Should Be 'success\1.sql'
			$so.Length -gt 0 | Should Be $true
			$so.Name | Should Be '1.sql'
			$so.LastWriteTime | Should Not BeNullOrEmpty
			$so.ByteArray | Should Not BeNullOrEmpty
			$so.Hash |Should Not BeNullOrEmpty
			$so.Parent.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'  
		}
		It "should test NewScript([string],[int]) method" {
			$so = $script:build.NewScript(@{FullName = $script1; Depth = 1})
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			$so.SourcePath | Should Be $script1
			$so.PackagePath | Should Be 'success\1.sql'
			$so.Length -gt 0 | Should Be $true
			$so.Name | Should Be '1.sql'
			$so.LastWriteTime | Should Not BeNullOrEmpty
			$so.ByteArray | Should Not BeNullOrEmpty
			$so.Hash |Should Not BeNullOrEmpty
			$so.Parent.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'  
			{ $script:pkg.Alter() } | Should Not Throw
			#Negative tests
			{ $script:build.NewScript($script1, 1) } | Should Throw
        }
		It "Should test AddScript([string]) method" {
			$f = [PowerUpFile]::new($script1, 'success\1.sql')
			$script:build.AddScript($f)
			#test build to contain the script
			'1.sql' | Should BeIn $script:build.Scripts.Name
			($script:build.Scripts | Measure-Object).Count | Should Be 1
		}
		It "Should test AddScript([string],[bool]) method" {
			$f = [PowerUpFile]::new($script1, 'success\1.sql')
			$script:build.AddScript($f,$false)
			#test build to contain the script
			'1.sql' | Should BeIn $script:build.Scripts.Name
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			$f2 = [PowerUpFile]::new($script1, 'success\1a.sql')
			{ $script:build.AddScript($f2, $false) } | Should Throw
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			$f3 = [PowerUpFile]::new($script1, 'success\1a.sql')
			$script:build.AddScript($f3, $true)
			($script:build.Scripts | Measure-Object).Count | Should Be 2
		}
	}
	Context "tests other methods" {
		BeforeEach {
			if ( $script:pkg.GetBuild('1.0')) { $script:pkg.RemoveBuild('1.0') }
			$b = $script:pkg.NewBuild('1.0')
			$f = [PowerUpScriptFile]::new($script1, 'success\1.sql')
			$b.AddScript($f)
			$script:build = $b
		}
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
        It "should test ToString method" {
            $script:build.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'  
        }
        It "should test HashExists method" {
            $f = [PowerUpScriptFile]::new(@{PackagePath = '1.sql'; SourcePath = '.\1.sql'; Hash = 'MyHash'})
            $script:build.AddScript($f, $true)
            $script:build.HashExists('MyHash') | Should Be $true
            $script:build.HashExists('MyHash2') | Should Be $false
            $script:build.HashExists('MyHash','.\1.sql') | Should Be $true
            $script:build.HashExists('MyHash','.\1a.sql') | Should Be $false
            $script:build.HashExists('MyHash2','.\1.sql') | Should Be $false
        }
        It "should test ScriptExists method" {
			$script:build.ScriptExists($script1) | Should Be $true
            $script:build.ScriptExists("$here\etc\install-tests\transactional-failure\1.sql") | Should Be $false
            { $script:build.ScriptExists("Nonexisting\path") } | Should Throw
		}
		It "should test ScriptModified method" {
			$script:build.ScriptModified($script1, $script1) | Should Be $false
			$script:build.ScriptModified($script2, $script1) | Should Be $true
			$script:build.ScriptModified($script2, $script2) | Should Be $false
		}
		It "should test SourcePathExists method" {
			$script:build.SourcePathExists($script1) | Should Be $true
			$script:build.SourcePathExists($script2) | Should Be $false
			$script:build.SourcePathExists('') | Should Be $false
		}
		It "should test PackagePathExists method" {
			$s1 = "success\1.sql"
			$s2 = "success\2.sql"
			$script:build.PackagePathExists($s1) | Should Be $true
			$script:build.PackagePathExists($s2) | Should Be $false
			#Overloads
			$script:build.PackagePathExists("a\$s1", 1) | Should Be $true
			$script:build.PackagePathExists("a\$s2", 1) | Should Be $false
		}
		It "should test GetPackagePath method" {
			$script:build.GetPackagePath() | Should Be 'content\1.0'
		}
		It "should test ExportToJson method" {
			$j = $script:build.ExportToJson() | ConvertFrom-Json
			$j.Scripts | Should Not BeNullOrEmpty
			$j.Build | Should Be '1.0'
			$j.PackagePath | Should Be '1.0'
			$j.CreatedDate | Should Not BeNullOrEmpty
		}
	}
	Context "tests Save/Alter methods" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
			if (Test-Path "$packageName.test.zip") { Remove-Item "$packageName.test.zip" }
		}
		It "should test Save method" {
			#Generate new package file
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
			if ( $script:pkg.GetBuild('1.0')) { $script:pkg.RemoveBuild('1.0') }
			$b = $script:pkg.NewBuild('1.0')
			$f = [PowerUpScriptFile]::new($script1, 'success\1.sql')
			$b.AddScript($f)
			$f = [PowerUpScriptFile]::new($script2, 'success\2.sql')
			$b.AddScript($f)
			$script:build = $b

			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:build.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
			'content\1.0\success\1.sql' | Should BeIn $results.Path
			'content\1.0\success\2.sql' | Should BeIn $results.Path
		}
		It "Should load package successfully after saving it" {
			$p = [PowerUpPackage]::new($packageName)
			$p.Builds.Scripts.Name | Should Not Be @('1.sql','2.sql') #Build.Save method does not write to package file
		}
		It "Should save and reopen the package under a different name" {
			#Generate new package file
			$p1 = [PowerUpPackage]::new()
			$p1.SaveToFile($packageName, $true)
			$p2 = [PowerUpPackage]::new($packageName)
			if ( $p2.GetBuild('1.0')) { $script:pkg.RemoveBuild('1.0') }
			$b = $p2.NewBuild('1.0')
			$f = [PowerUpScriptFile]::new($script1, 'success\1.sql')
			$b.AddScript($f)
			$f = [PowerUpScriptFile]::new($script2, 'success\2.sql')
			$b.AddScript($f)
			$p2.SaveToFile("$packageName.test.zip")
			$script:pkg = [PowerUpPackage]::new("$packageName.test.zip")
			$script:build = $script:pkg.GetBuild('1.0')
		}
		$oldResults = Get-ArchiveItem "$packageName.test.zip" | Where-Object IsFolder -eq $false
		#Sleep 1 second to ensure that modification date is changed
		Start-Sleep -Seconds 2
		It "should test Alter method" {
			$f = [PowerUpScriptFile]::new($script3, 'success\3.sql')
			$script:build.AddScript($f)
			{ $script:build.Alter() } | Should Not Throw
			$results = Get-ArchiveItem "$packageName.test.zip"
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
			'content\1.0\success\1.sql' | Should BeIn $results.Path
			'content\1.0\success\2.sql' | Should BeIn $results.Path
		}
		It "Should load package successfully after saving it" {
			$p = [PowerUpPackage]::new("$packageName.test.zip")
			$p.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
		}
		# Testing file contents to be updated by the Save method
		$results = Get-ArchiveItem "$packageName.test.zip" | Where-Object IsFolder -eq $false
		$saveTestsErrors = 0
		#should trigger file updates for build files and module files
		foreach ($result in ($oldResults | Where-Object { $_.Path -like 'content\1.0\success' -or $_.Path -like 'Modules\PowerUp\*'  } )) {
			if ($result.LastWriteTime -ge ($results | Where-Object Path -eq $result.Path).LastWriteTime) {
				It "Should have updated Modified date for file $($result.Path)" {
					$result.LastWriteTime -lt ($results | Where-Object Path -eq $result.Path).LastWriteTime | Should Be $true
				}
				$saveTestsErrors++
			}
		}
		if ($saveTestsErrors -eq 0) {
			It "Ran silently $($oldResults.Length) file modification tests" {
				$saveTestsErrors | Should be 0
			}
		}
    }
}

Describe "PowerUpFile class tests" -Tag $commandName, UnitTests, PowerUpFile {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "tests PowerUpFile object creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpFile object" {
			$f = [PowerUpFile]::new()
			# $f | Should Not BeNullOrEmpty
			$f.SourcePath | Should BeNullOrEmpty
			$f.PackagePath | Should BeNullOrEmpty
			$f.Length | Should Be 0 
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
		}
		It "Should create new PowerUpFile object from path" {
			$f = [PowerUpFile]::new($script1, '1.sql')
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length -gt 0 | Should Be $true
			$f.Name | Should Be '1.sql'
			$f.LastWriteTime | Should Not BeNullOrEmpty
			$f.ByteArray | Should Not BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
			#Negative tests
			{ [PowerUpFile]::new('Nonexisting\path', '1.sql') } | Should Throw
			{ [PowerUpFile]::new($script1, '') } | Should Throw
			{ [PowerUpFile]::new('', '1.sql') } | Should Throw
		}
		It "Should create new PowerUpFile object using custom object" {
			$obj = @{
				SourcePath  = $script1
				packagePath = '1.sql'
				Hash        = 'MyHash'
			}
			$f = [PowerUpFile]::new($obj)
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length | Should Be 0
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty

			#Negative tests
			$obj = @{ foo = 'bar'}
			{ [PowerUpFile]::new($obj) } | Should Throw
		}
		It "Should create new PowerUpFile object from zipfile using custom object" {
			$p = [PowerUpPackage]::new()
			$null = $p.NewBuild('1.0').NewScript($script1, 1)
			$p.SaveToFile($packageName)
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			try {
				$stream = [FileStream]::new($packageName, $writeMode)
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
				try {
					$zipEntry = $zip.Entries | Where-Object FullName -eq 'content\1.0\success\1.sql'
					$obj = @{
						SourcePath  = $script1
						packagePath = '1.sql'
						Hash        = 'MyHash'
					}
					# { [PowerUpFile]::new($obj, $zipEntry) } | Should Throw #hash is invalid
					# $obj.Hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1)))
					$f = [PowerUpFile]::new($obj, $zipEntry)
					$f | Should Not BeNullOrEmpty
					$f.SourcePath | Should Be $script1
					$f.PackagePath | Should Be '1.sql'
					$f.Length -gt 0 | Should Be $true
					$f.Name | Should Be '1.sql'
					$f.LastWriteTime | Should Not BeNullOrEmpty
					$f.ByteArray | Should Not BeNullOrEmpty
					# $f.Hash | Should Be $obj.Hash
					$f.Hash | Should BeNullOrEmpty
					$f.Parent | Should BeNullOrEmpty
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}

			#Negative tests
			$badobj = @{ foo = 'bar'}
			{ [PowerUpFile]::new($badobj, $zip) } | Should Throw #object is incorrect
			{ [PowerUpFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
		}
	}
	Context "tests other PowerUpFile methods" {
		BeforeEach {
			if ( $script:build.GetFile('success\1.sql', 'Scripts')) { $script:build.RemoveFile('success\1.sql', 'Scripts') }
			$script:file = $script:build.NewFile($script1, 'success\1.sql', 'Scripts')
			$script:build.Alter()
		}
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:build = $script:pkg.NewBuild('1.0')
			$script:pkg.SaveToFile($packageName, $true)
		}
		It "should test ToString method" {
			$script:file.ToString() | Should Be 'success\1.sql'  
		}
		It "should test GetContent method" {
			$script:file.GetContent() | Should BeLike 'CREATE TABLE dbo.a (a int)*'
			#ToDo: add files with different encodings
		}
		It "should test SetContent method" {
			$oldData = $script:file.ByteArray
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			$script:file.ByteArray | Should Not Be $oldData
			$script:file.ByteArray | Should Not BeNullOrEmpty
		}
		It "should test ExportToJson method" {
			$j = $script:file.ExportToJson() | ConvertFrom-Json
			$j.PackagePath | Should Be 'success\1.sql'
			# $j.Hash | Should Be ([PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1))))
			$j.SourcePath | Should Be $script1
		}
		It "should test Save method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:file.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			$oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
			# { $p = [PowerUpPackage]::new($packageName) } | Should Throw #Because of the hash mismatch - package file is not updated in Save()
		}
		It "should test Alter method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			{ $script:file.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			$oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
		}
	}
}

Describe "PowerUpScriptFile class tests" -Tag $commandName, UnitTests, PowerUpFile, PowerUpScriptFile {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "tests PowerUpScriptFile object creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpScriptFile object" {
			$f = [PowerUpScriptFile]::new()
			# $f | Should Not BeNullOrEmpty
			$f.SourcePath | Should BeNullOrEmpty
			$f.PackagePath | Should BeNullOrEmpty
			$f.Length | Should Be 0 
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
		}
		It "Should create new PowerUpScriptFile object from path" {
			$f = [PowerUpScriptFile]::new($script1, '1.sql')
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length -gt 0 | Should Be $true
			$f.Name | Should Be '1.sql'
			$f.LastWriteTime | Should Not BeNullOrEmpty
			$f.ByteArray | Should Not BeNullOrEmpty
			$f.Hash | Should Not BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
			#Negative tests
			{ [PowerUpScriptFile]::new('Nonexisting\path', '1.sql') } | Should Throw
			{ [PowerUpScriptFile]::new($script1, '') } | Should Throw
			{ [PowerUpScriptFile]::new('', '1.sql') } | Should Throw
		}
		It "Should create new PowerUpScriptFile object using custom object" {
			$obj = @{
				SourcePath  = $script1
				packagePath = '1.sql'
				Hash        = 'MyHash'
			}
			$f = [PowerUpScriptFile]::new($obj)
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length | Should Be 0
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should Be 'MyHash'
			$f.Parent | Should BeNullOrEmpty

			#Negative tests
			$obj = @{ foo = 'bar'}
			{ [PowerUpScriptFile]::new($obj) } | Should Throw
		}
		It "Should create new PowerUpScriptFile object from zipfile using custom object" {
			$p = [PowerUpPackage]::new()
			$null = $p.NewBuild('1.0').NewScript($script1, 1)
			$p.SaveToFile($packageName)
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			try {
				$stream = [FileStream]::new($packageName, $writeMode)
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
				try {
					$zipEntry = $zip.Entries | Where-Object FullName -eq 'content\1.0\success\1.sql'
					$obj = @{
						SourcePath  = $script1
						packagePath = '1.sql'
						Hash        = 'MyHash'
					}
					{ [PowerUpScriptFile]::new($obj, $zipEntry) } | Should Throw #hash is invalid
					$obj.Hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1)))
					$f = [PowerUpScriptFile]::new($obj, $zipEntry)
					$f | Should Not BeNullOrEmpty
					$f.SourcePath | Should Be $script1
					$f.PackagePath | Should Be '1.sql'
					$f.Length -gt 0 | Should Be $true
					$f.Name | Should Be '1.sql'
					$f.LastWriteTime | Should Not BeNullOrEmpty
					$f.ByteArray | Should Not BeNullOrEmpty
					$f.Hash | Should Be $obj.Hash
					$f.Parent | Should BeNullOrEmpty
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}

			#Negative tests
			$badobj = @{ foo = 'bar'}
			{ [PowerUpScriptFile]::new($badobj, $zip) } | Should Throw #object is incorrect
			{ [PowerUpScriptFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
		}
	}
	Context "tests overloaded PowerUpScriptFile methods" {
		BeforeEach {
			if ( $script:build.GetFile('success\1.sql', 'Scripts')) { $script:build.RemoveFile('success\1.sql', 'Scripts') }
			$script:file = $script:build.NewFile($script1, 'success\1.sql', 'Scripts', [PowerUpScriptFile])
			$script:build.Alter()
		}
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:build = $script:pkg.NewBuild('1.0')
			$script:pkg.SaveToFile($packageName, $true)
		}
		It "should test SetContent method" {
			$oldData = $script:file.ByteArray
			$oldHash = $script:file.Hash
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			$script:file.ByteArray | Should Not Be $oldData
			$script:file.ByteArray | Should Not BeNullOrEmpty
			$script:file.Hash | Should Not Be $oldHash
			$script:file.Hash | Should Not BeNullOrEmpty
		}
		It "should test ExportToJson method" {
			$j = $script:file.ExportToJson() | ConvertFrom-Json
			$j.PackagePath | Should Be 'success\1.sql'
			$j.Hash | Should Be ([PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1))))
			$j.SourcePath | Should Be $script1
		}
		It "should test Save method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:file.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			$oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
			{ [PowerUpPackage]::new($packageName) } | Should Throw #Because of the hash mismatch - package file is not updated in Save()
		}
		It "should test Alter method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			{ $script:file.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
			$oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
			$p = [PowerUpPackage]::new($packageName)
			$p.Builds[0].Scripts[0].GetContent() | Should BeLike 'CREATE TABLE dbo.c (a int)*'
		}
	}
}
Describe "PowerUpRootFile class tests" -Tag $commandName, UnitTests, PowerUpFile, PowerUpRootFile {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "tests PowerUpFile object creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpRootFile object" {
			$f = [PowerUpRootFile]::new()
			# $f | Should Not BeNullOrEmpty
			$f.SourcePath | Should BeNullOrEmpty
			$f.PackagePath | Should BeNullOrEmpty
			$f.Length | Should Be 0 
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
		}
		It "Should create new PowerUpRootFile object from path" {
			$f = [PowerUpRootFile]::new($script1, '1.sql')
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length -gt 0 | Should Be $true
			$f.Name | Should Be '1.sql'
			$f.LastWriteTime | Should Not BeNullOrEmpty
			$f.ByteArray | Should Not BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
			#Negative tests
			{ [PowerUpRootFile]::new('Nonexisting\path', '1.sql') } | Should Throw
			{ [PowerUpRootFile]::new($script1, '') } | Should Throw
			{ [PowerUpRootFile]::new('', '1.sql') } | Should Throw
		}
		It "Should create new PowerUpRootFile object using custom object" {
			$obj = @{
				SourcePath  = $script1
				packagePath = '1.sql'
				Hash        = 'MyHash'
			}
			$f = [PowerUpRootFile]::new($obj)
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length | Should Be 0
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty

			#Negative tests
			$obj = @{ foo = 'bar'}
			{ [PowerUpFile]::new($obj) } | Should Throw
		}
		It "Should create new PowerUpRootFile object from zipfile using custom object" {
			$p = [PowerUpPackage]::new()
			$null = $p.NewBuild('1.0').NewScript($script1, 1)
			$p.SaveToFile($packageName)
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			try {
				$stream = [FileStream]::new($packageName, $writeMode)
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
				try {
					$zipEntry = $zip.Entries | Where-Object FullName -eq 'content\1.0\success\1.sql'
					$obj = @{
						SourcePath  = $script1
						packagePath = '1.sql'
						Hash        = 'MyHash'
					}
					$f = [PowerUpRootFile]::new($obj, $zipEntry)
					$f | Should Not BeNullOrEmpty
					$f.SourcePath | Should Be $script1
					$f.PackagePath | Should Be '1.sql'
					$f.Length -gt 0 | Should Be $true
					$f.Name | Should Be '1.sql'
					$f.LastWriteTime | Should Not BeNullOrEmpty
					$f.ByteArray | Should Not BeNullOrEmpty
					$f.Hash | Should BeNullOrEmpty
					$f.Parent | Should BeNullOrEmpty
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}

			#Negative tests
			$badobj = @{ foo = 'bar'}
			{ [PowerUpRootFile]::new($badobj, $zip) } | Should Throw #object is incorrect
			{ [PowerUpRootFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
		}
	}
	Context "tests overloaded PowerUpRootFile methods" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName, $true)
			$script:file = $script:pkg.GetFile('Deploy.ps1', 'DeployFile')
		}
		It "should test SetContent method" {
			$oldData = $script:file.ByteArray
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			$script:file.ByteArray | Should Not Be $oldData
			$script:file.ByteArray | Should Not BeNullOrEmpty
			$script:file.Hash | Should BeNullOrEmpty
		}
		It "should test ExportToJson method" {
			$j = $script:file.ExportToJson() | ConvertFrom-Json
			$j.PackagePath | Should Be 'Deploy.ps1'
			$j.SourcePath | Should Be (Get-PowerUpModuleFileList | Where-Object {$_.Type -eq 'Misc' -and $_.Name -eq 'Deploy.ps1'}).FullName
		}
		It "should test Save method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:file.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
			$oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
		}
		It "should test Alter method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			{ $script:file.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
			$oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
		}
	}
}

Describe "PowerUpConfig class tests" -Tag $commandName, UnitTests, PowerUpConfig {
	Context "tests PowerUpConfig constructors" {
		It "Should return an empty config by default" {
			$result = [PowerUpConfig]::new()
			$result.ApplicationName | Should Be $null
			$result.SqlInstance | Should Be $null
			$result.Database | Should Be $null
			$result.DeploymentMethod | Should Be $null
			$result.ConnectionTimeout | Should Be $null
			$result.ExecutionTimeout | Should Be $null
			$result.Encrypt | Should Be $null
			$result.Credential | Should Be $null
			$result.Username | Should Be $null
			$result.Password | Should Be $null
			$result.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$result.Silent | Should Be $null
			$result.Variables | Should Be $null
		}
		It "Should return empty configuration from empty config file" {
			$result = [PowerUpConfig]::new((Get-Content "$here\etc\empty_config.json" -Raw))
			$result.ApplicationName | Should Be $null
			$result.SqlInstance | Should Be $null
			$result.Database | Should Be $null
			$result.DeploymentMethod | Should Be $null
			$result.ConnectionTimeout | Should Be $null
			$result.ExecutionTimeout | Should Be $null
			$result.Encrypt | Should Be $null
			$result.Credential | Should Be $null
			$result.Username | Should Be $null
			$result.Password | Should Be $null
			$result.SchemaVersionTable | Should Be $null
			$result.Silent | Should Be $null
			$result.Variables | Should Be $null
		}
		It "Should return all configurations from the config file" {
			$result = [PowerUpConfig]::new((Get-Content "$here\etc\full_config.json" -Raw))
			$result.ApplicationName | Should Be "MyTestApp"
			$result.SqlInstance | Should Be "TestServer"
			$result.Database | Should Be "MyTestDB"
			$result.DeploymentMethod | Should Be "SingleTransaction"
			$result.ConnectionTimeout | Should Be 40
			$result.ExecutionTimeout | Should Be $null
			$result.Encrypt | Should Be $null
			$result.Credential | Should Be $null
			$result.Username | Should Be "TestUser"
			$result.Password | Should Be "TestPassword"
			$result.SchemaVersionTable | Should Be "test.Table"
			$result.Silent | Should Be $true
			$result.Variables | Should Be $null
		}
	}
	Context "tests other methods of PowerUpConfig" {
		It "should test AsHashtable method" {
			$result = [PowerUpConfig]::new((Get-Content "$here\etc\full_config.json" -Raw)).AsHashtable()
			$result.GetType().Name | Should Be 'hashtable'
			$result.ApplicationName | Should Be "MyTestApp"
			$result.SqlInstance | Should Be "TestServer"
			$result.Database | Should Be "MyTestDB"
			$result.DeploymentMethod | Should Be "SingleTransaction"
			$result.ConnectionTimeout | Should Be 40
			$result.ExecutionTimeout | Should Be $null
			$result.Encrypt | Should Be $null
			$result.Credential | Should Be $null
			$result.Username | Should Be "TestUser"
			$result.Password | Should Be "TestPassword"
			$result.SchemaVersionTable | Should Be "test.Table"
			$result.Silent | Should Be $true
			$result.Variables | Should Be $null
		}
		It "should test SetValue method" {
			$config = [PowerUpConfig]::new((Get-Content "$here\etc\full_config.json" -Raw))
			#String property
			$config.SetValue('ApplicationName', 'MyApp2')
			$config.ApplicationName | Should Be 'MyApp2'
			$config.SetValue('ApplicationName', $null)
			$config.ApplicationName | Should Be $null
			$config.SetValue('ApplicationName', 123)
			$config.ApplicationName | Should Be '123'
			#Int property
			$config.SetValue('ConnectionTimeout', 11)
			$config.ConnectionTimeout | Should Be 11
			$config.SetValue('ConnectionTimeout', $null)
			$config.ConnectionTimeout | Should Be $null
			$config.SetValue('ConnectionTimeout', '123')
			$config.ConnectionTimeout | Should Be 123
			{ $config.SetValue('ConnectionTimeout', 'string') } | Should Throw
			#Bool property
			$config.SetValue('Silent', $false)
			$config.Silent | Should Be $false
			$config.SetValue('Silent', $null)
			$config.Silent | Should Be $null
			$config.SetValue('Silent', 2)
			$config.Silent | Should Be $true
			$config.SetValue('Silent', 0)
			$config.Silent | Should Be $false
			$config.SetValue('Silent', 'string')
			$config.Silent | Should Be $true
			#Negatives
			{ $config.SetValue('AppplicationName', 'MyApp3') } | Should Throw
		}
		It "should test ExportToJson method" {
			$result = [PowerUpConfig]::new((Get-Content "$here\etc\full_config.json" -Raw)).ExportToJson() | ConvertFrom-Json -ErrorAction Stop
			$result.ApplicationName | Should Be "MyTestApp"
			$result.SqlInstance | Should Be "TestServer"
			$result.Database | Should Be "MyTestDB"
			$result.DeploymentMethod | Should Be "SingleTransaction"
			$result.ConnectionTimeout | Should Be 40
			$result.ExecutionTimeout | Should Be $null
			$result.Encrypt | Should Be $null
			$result.Credential | Should Be $null
			$result.Username | Should Be "TestUser"
			$result.Password | Should Be "TestPassword"
			$result.SchemaVersionTable | Should Be "test.Table"
			$result.Silent | Should Be $true
			$result.Variables | Should Be $null
		}
		It "should test Merge method" {
			$config = [PowerUpConfig]::new((Get-Content "$here\etc\full_config.json" -Raw))
			$hashtable = @{
				ApplicationName = 'MyTestApp2'
				ConnectionTimeout = 0
				SqlInstance = $null
				Silent = $false
				ExecutionTimeout = 20
			}
			$config.Merge($hashtable)
			$config.ApplicationName | Should Be "MyTestApp2"
			$config.SqlInstance | Should Be $null
			$config.Database | Should Be "MyTestDB"
			$config.DeploymentMethod | Should Be "SingleTransaction"
			$config.ConnectionTimeout | Should Be 0
			$config.ExecutionTimeout | Should Be 20
			$config.Encrypt | Should Be $null
			$config.Credential | Should Be $null
			$config.Username | Should Be "TestUser"
			$config.Password | Should Be "TestPassword"
			$config.SchemaVersionTable | Should Be "test.Table"
			$config.Silent | Should Be $false
			$config.Variables | Should Be $null
			#negative
			{ $config.Merge(@{foo = 'bar'}) } | Should Throw
			{ $config.Merge($null) } | Should Throw
		}
	}
	Context "tests Save/Alter methods" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "should test Save method" {
			#Generate new package file
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.Configuration.ApplicationName = 'TestApp2'
			$script:pkg.SaveToFile($packageName)

			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					$script:pkg.Configuration.Save($zip)
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
		}
		It "Should load package successfully after saving it" {
			$script:pkg = [PowerUpPackage]::new($packageName)
			$script:pkg.Configuration.ApplicationName | Should Be 'TestApp2'
		}
		It "should test Alter method" {
			$script:pkg.Configuration.ApplicationName = 'TestApp3'
			$script:pkg.Configuration.Alter()
			$results = Get-ArchiveItem "$packageName"
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
		}
		It "Should load package successfully after saving it" {
			$p = [PowerUpPackage]::new($packageName)
			$p.Configuration.ApplicationName | Should Be 'TestApp3'
		}
	}
	Context "tests static methods of PowerUpConfig" {
		It "should test static GetDeployFile method" {
			$f = [PowerUpConfig]::GetDeployFile()
			$f.Type | Should Be 'Misc'
			$f.Path | Should BeLike '*\Deploy.ps1'
			$f.Name | Should Be 'Deploy.ps1'
		}
		It "should test static FromFile method" {
			$result = [PowerUpConfig]::FromFile("$here\etc\full_config.json")
			$result.ApplicationName | Should Be "MyTestApp"
			$result.SqlInstance | Should Be "TestServer"
			$result.Database | Should Be "MyTestDB"
			$result.DeploymentMethod | Should Be "SingleTransaction"
			$result.ConnectionTimeout | Should Be 40
			$result.ExecutionTimeout | Should Be $null
			$result.Encrypt | Should Be $null
			$result.Credential | Should Be $null
			$result.Username | Should Be "TestUser"
			$result.Password | Should Be "TestPassword"
			$result.SchemaVersionTable | Should Be "test.Table"
			$result.Silent | Should Be $true
			$result.Variables | Should Be $null
			#negatives
			{ [PowerUpConfig]::FromFile("$here\etc\notajsonfile.json") } | Should Throw
			{ [PowerUpConfig]::FromFile("nonexisting\file") } | Should Throw
			{ [PowerUpConfig]::FromFile($null) } | Should Throw
		}
		It "should test static FromJsonString method" {
			$result = [PowerUpConfig]::FromJsonString((Get-Content "$here\etc\full_config.json" -Raw))
			$result.ApplicationName | Should Be "MyTestApp"
			$result.SqlInstance | Should Be "TestServer"
			$result.Database | Should Be "MyTestDB"
			$result.DeploymentMethod | Should Be "SingleTransaction"
			$result.ConnectionTimeout | Should Be 40
			$result.ExecutionTimeout | Should Be $null
			$result.Encrypt | Should Be $null
			$result.Credential | Should Be $null
			$result.Username | Should Be "TestUser"
			$result.Password | Should Be "TestPassword"
			$result.SchemaVersionTable | Should Be "test.Table"
			$result.Silent | Should Be $true
			$result.Variables | Should Be $null
			#negatives
			{ [PowerUpConfig]::FromJsonString((Get-Content "$here\etc\notajsonfile.json" -Raw)) } | Should Throw
			{ [PowerUpConfig]::FromJsonString($null) } | Should Throw
			{ [PowerUpConfig]::FromJsonString('') } | Should Throw
		}
	}
}