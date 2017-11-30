﻿# constants
if (Test-Path C:\temp\PUconstants.ps1) {
	Write-Verbose "C:\temp\PUconstants.ps1 found."
	. C:\temp\constants.ps1
}
elseif (Test-Path "$PSScriptRoot\constants.local.ps1") {
	Write-Verbose "tests\constants.local.ps1 found."
	. "$PSScriptRoot\constants.local.ps1"
}
else {
	$script:instance1 = "localhost\sql2016"
	$script:database1 = "tempdb"
}