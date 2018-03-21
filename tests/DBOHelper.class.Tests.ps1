Param (
	[switch]$Batch
)

$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }

if (!$Batch) {
	# Is not a part of the global batch => import module
	#Explicitly import the module for testing
	Import-Module "$here\..\PowerUp.psd1" -Force
	Import-Module "$here\etc\modules\ZipHelper" -Force
}
else {
	# Is a part of a batch, output some eye-catching happiness
	Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\PowerUpHelper.class.ps1"
$script1 = "$here\etc\install-tests\success\1.sql"
$script2 = "$here\etc\install-tests\success\2.sql"
$archiveName = "$here\etc\PowerUpHelper.zip"
$sqlName = "$here\etc\PowerUpHelper.sql"

$encodings = @(
	'ASCII'
	'Unicode'
	'BigEndianUnicode'
	'UTF32'
	'UTF7'
	'UTF8'
)
$encodedFiles = @(
	"$here\etc\encoding-tests\1252.txt"
	"$here\etc\encoding-tests\UTF8-BOM.txt"
	"$here\etc\encoding-tests\UTF8-NoBOM.txt"
	"$here\etc\encoding-tests\UTF16-BE.txt"
	"$here\etc\encoding-tests\UTF16-LE.txt"
	"$here\etc\encoding-tests\UTF16-NoBOM.txt"
)


Describe "PowerUpHelper class tests" -Tag $commandName, UnitTests, PowerUpHelper {
	Context "tests SplitRelativePath method" {
		It "should validate positive tests" {
			[PowerUpHelper]::SplitRelativePath('3\2\1\file.txt', 0) | Should Be 'file.txt'
			[PowerUpHelper]::SplitRelativePath('3\2\1\file.txt', 1) | Should Be '1\file.txt'
			[PowerUpHelper]::SplitRelativePath('3\2\1\file.txt', 3) | Should Be '3\2\1\file.txt'
		}
		It "should validate negative tests" {
			{ [PowerUpHelper]::SplitRelativePath('3\2\1\file.txt', 4) } | Should Throw
			{ [PowerUpHelper]::SplitRelativePath($null, 1) } | Should Throw
		}
	}
	Context "tests GetBinaryFile method" {
		It "should validate positive tests" {
			[PowerUpHelper]::GetBinaryFile($script1) | Should Not BeNullOrEmpty
			#Verifying that the threads are closed
			{ [PowerUpHelper]::GetBinaryFile($script1) } | Should Not Throw
		}
		It "should validate negative tests" {
			{ [PowerUpHelper]::GetBinaryFile('nonexisting\path') } | Should Throw
			{ [PowerUpHelper]::SplitRelativePath($null) } | Should Throw
		}
	}
	Context "tests ReadDeflateStream method" {
		BeforeAll {
			#Create the archive 
			Compress-Archive -Path $script1 -DestinationPath $archiveName
		}
		AfterAll {
			#Remove temporary file 
			Remove-Item $archiveName
		}
		It "should validate positive tests" {
			$zip = [Zipfile]::OpenRead($archiveName)
			try {
				[PowerUpHelper]::ReadDeflateStream($zip.Entries[0].Open()) | Should Not BeNullOrEmpty 
			}
			catch { throw $_ }
			finally { $zip.Dispose() }
		
			#Verifying that the threads are closed
			$zip = [Zipfile]::OpenRead($archiveName)
			try {
				{ [PowerUpHelper]::ReadDeflateStream($zip.Entries[0].Open()) } | Should Not Throw
			}
			catch { throw $_ }
			finally { $zip.Dispose() }
		}
		It "should validate negative tests" {
			$zip = [Zipfile]::OpenRead($archiveName).Dispose()
			{ [PowerUpHelper]::ReadDeflateStream($zip.Entries[0].Open()) } | Should Throw
			{ [PowerUpHelper]::ReadDeflateStream($null) } | Should Throw
		}
	}
	Context "tests GetArchiveItems method" {
		BeforeAll {
			#Create the archive 
			Compress-Archive -Path $script1, $script2 -DestinationPath $archiveName
		}
		AfterAll {
			#Remove temporary file 
			Remove-Item $archiveName
		}
		It "should validate positive tests" {
			$results = [PowerUpHelper]::GetArchiveItems($archiveName)
			'1.sql' | Should BeIn $results.FullName
			'2.sql' | Should BeIn $results.FullName
		
			#Verifying that the threads are closed
			{ [PowerUpHelper]::GetArchiveItems($archiveName) } | Should Not Throw
		}
		It "should validate negative tests" {
			{ [PowerUpHelper]::GetArchiveItems($null) } | Should Throw
			{ [PowerUpHelper]::GetArchiveItems('nonexisting\path') } | Should Throw
		}
	}
	Context "tests GetArchiveItem method" {
		BeforeAll {
			#Create the archive 
			Compress-Archive -Path $script1, $script2 -DestinationPath $archiveName
		}
		AfterAll {
			#Remove temporary file 
			Remove-Item $archiveName
		}
		It "should validate positive tests" {
			$results = [PowerUpHelper]::GetArchiveItem($archiveName, '1.sql')
			'1.sql' | Should BeIn $results.FullName
			'2.sql' | Should Not BeIn $results.FullName
			foreach ($result in $results) {
				$result.ByteArray | Should Not BeNullOrEmpty
			}

			$results = [PowerUpHelper]::GetArchiveItem($archiveName, @('1.sql', '2.sql'))
			'1.sql' | Should BeIn $results.FullName
			'2.sql' | Should BeIn $results.FullName
			foreach ($result in $results) {
				$result.ByteArray | Should Not BeNullOrEmpty
			}
		}
		It "should validate negative tests" {
			{ [PowerUpHelper]::GetArchiveItem($null, '1.sql') } | Should Throw
			{ [PowerUpHelper]::GetArchiveItem('nonexisting\path', '1.sql') } | Should Throw
			[PowerUpHelper]::GetArchiveItem($archiveName, $null) | Should BeNullOrEmpty
			[PowerUpHelper]::GetArchiveItem($archiveName, 'nonexisting\path') | Should BeNullOrEmpty
			[PowerUpHelper]::GetArchiveItem($archiveName, '') | Should BeNullOrEmpty
		}
	}
	Context "tests WriteZipFile method" {
		AfterEach {
			#Remove temporary file 
			Remove-Item $archiveName
		}
		It "should validate positive tests" {
			#Create the archive 
			$content = [byte[]]@(66, 67, 68)#Open new file stream
			$writeMode = [System.IO.FileMode]::CreateNew
			$stream = [FileStream]::new($archiveName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Create)
				try {
					[PowerUpHelper]::WriteZipFile($zip, 'asd.txt', $content)
					[PowerUpHelper]::WriteZipFile($zip, 'folder\asd.txt', $content)
					[PowerUpHelper]::WriteZipFile($zip, 'folder1\folder2\null.txt', [byte[]]::new(0))
				}
				catch { throw $_ }
				finally { $zip.Dispose() }	
			}
			catch { throw $_ }
			finally { $stream.Dispose()	}
			$results = [PowerUpHelper]::GetArchiveItems($archiveName)
			'asd.txt' | Should BeIn $results.FullName
			'folder\asd.txt' | Should BeIn $results.FullName
			'folder1\folder2\null.txt' | Should BeIn $results.FullName
		}
		It "should validate negative tests" {
			#Create the archive 
			$content = [byte[]]@(66, 67, 68)#Open new file stream
			$writeMode = [System.IO.FileMode]::CreateNew
			$stream = [FileStream]::new($archiveName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Create)
				try {
					[PowerUpHelper]::WriteZipFile($zip, 'asd.txt', $content)
					{ [PowerUpHelper]::WriteZipFile($zip, 'folder\asd.txt', 'asd') } | Should Throw
					{ [PowerUpHelper]::WriteZipFile($zip, 'null2.txt', $null) } | Should Throw
					{ [PowerUpHelper]::WriteZipFile($zip, '..\2.txt', $content) } | Should Throw
					{ [PowerUpHelper]::WriteZipFile($zip, '.\2.txt', $content) } | Should Throw
					{ [PowerUpHelper]::WriteZipFile($zip, '\2.txt', $content) } | Should Throw
				}
				catch { throw $_ }
				finally { $zip.Dispose() }	
			}
			catch { throw $_ }
			finally { $stream.Dispose()	}
			$results = [PowerUpHelper]::GetArchiveItems($archiveName)
			'asd.txt' | Should BeIn $results.FullName
			'folder\asd.txt' | Should Not BeIn $results.FullName
			'null2.txt' | Should BeIn $results.FullName #This is weird, but that's how it works
			'2.txt' | Should Not BeIn $results.FullName
			'..\2.txt' | Should Not BeIn $results.FullName
			'.\2.txt' | Should Not BeIn $results.FullName
			'\2.txt' | Should Not BeIn $results.FullName
		}
	}
	Context "tests ToHexString method" {
		It "should validate positive tests" {
			[PowerUpHelper]::ToHexString('') | Should Be '0x00'
			[PowerUpHelper]::ToHexString([byte[]]@(1, 2, 3, 4)) | Should Be '0x01020304'
			[PowerUpHelper]::ToHexString($null) | Should Be '0x00'
			[PowerUpHelper]::ToHexString('0xFF') | Should Be '0xFF'
		}
		It "should validate negative tests" {
			{ [PowerUpHelper]::ToHexString('0xAAAA') } | Should Throw
			{ [PowerUpHelper]::ToHexString('qwe') } | Should Throw
		}
	}
	Context "tests DecodeBinaryText method" {
		AfterAll {
			Remove-Item $sqlName
		}

		$string = 'SELECT foo FROM bar'
		$h = [PowerUpHelper]
		$enc = [System.Text.Encoding]
		foreach ($encoding in $encodings) {
			It "should convert from binary string encoded as $encoding" {
				$h::DecodeBinaryText($enc::$encoding.GetPreamble() + $enc::$encoding.GetBytes($string)) | Should BeExactly $string
			}
			It "should convert from file encoded as $encoding" {
				$string | Out-File $sqlName -Encoding $encoding -Force -NoNewline
				$sqlName | Should -FileContentMatchExactly ([regex]::Escape($h::DecodeBinaryText($h::GetBinaryFile($sqlName))))
			}
		}
		foreach ($encodedFile in $encodedFiles) {
			It "should read encoded file $encodedFile" {
				$h::DecodeBinaryText($h::GetBinaryFile($encodedFile)) | Should BeExactly $string
				$encodedFile | Should -FileContentMatchExactly ([regex]::Escape($h::DecodeBinaryText($h::GetBinaryFile($encodedFile))))
			}
		}

		It "should validate negative tests" {
			$h = [PowerUpHelper]
			{ $h::DecodeBinaryText('0xAAAA') } | Should Throw
			{ $h::DecodeBinaryText('NotAByte') } | Should Throw
			{ $h::DecodeBinaryText($enc::UTF8.GetBytes($null)) } | Should Throw
		}
	}
}