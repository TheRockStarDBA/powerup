| master | development |
|---|---|
| [![Build status](https://ci.appveyor.com/api/projects/status/m0ml0392r631tp60/branch/master?svg=true)](https://ci.appveyor.com/project/nvarscar/powerup/branch/master) | [![Build status](https://ci.appveyor.com/api/projects/status/m0ml0392r631tp60/branch/development?svg=true)](https://ci.appveyor.com/project/nvarscar/powerup/branch/development) |

# DBOps
DBOps is a Powershell module that provides Continuous Integration/Continuous Deployment capabilities for SQL database deployments. In addition to easy-to-use deployment functions, it provides tracking functionality, ensuring that each script is deployed only once and in due order. It will also grant you with ability to organize scripts into builds and deploy them in a repeatable manner on top of any previously deployed version.

The deployment functionality of the module is provided by [DbUp](https://github.com/DbUp/DbUp) .Net library, which has proven its flexibility and reliability during deployments. 

Currently supported RDBMS:
* SQL Server

## Features
The most notable features of the module:

* No scripting experience required - the module is designed around usability and functionality
* Introduces an option to aggregate source scripts from multiple sources into a single ready-to-deploy file
* Can detect new/changed files in your source code folder and generate a new deployment build based on those files
* Introduces optional internal build system: older builds are kept inside the deployment package ensuring smooth and errorless deployments
* Reliably deploys the scripts in a consistent manner - all the scripts are executed in alphabetical order one build at a time
* Can be deployed without the module installed in the system - module itself is integrated into the deployment package
* Transactionality of the deployments/migrations: every build can be deployed as a part of a single transaction, rolling back unsuccessful deployments
* Dynamically change your code based on custom variables - use `#{customVarName}` tokens to define variables inside the scripts or execution parameters
* Packages are fully compatible with Octopus Deploy deployments: all packages are in essence zip archives with Deploy.ps1 file that initiates deployment


## System requirements

* Powershell 5.0 or higher

## Installation
```powershell
git clone https://github.com/nvarscar/powerup.git dbops
Import-Module .\dbops
```

## Usage scenarios

* Ad-hoc deployments of any scale without the necessity of executing the code manually
* Delivering new version of the database schema in a consistent manner to multiple environments
* Build/Test/Deploy stage inside of Continuous Integration/Continuous Delivery pipelines
* Dynamic deployment based on modified files in the source folder

## Examples

```powershell
# Quick deployment without tracking deployment history
Invoke-DBODeployment -ScriptPath C:\temp\myscripts -SqlInstance server1 -Database MyDB -SchemaVersionTable $null

# Deployment using packages & builds with keeping track of deployment history in dbo.SchemaVersions
New-DBOPackage Deploy.zip -ScriptPath C:\temp\myscripts | Install-DBOPackage -SqlInstance server1 -Database MyDB

# Create new deployment package with predefined configuration and deploy it replacing #{dbName} tokens with corresponding values
New-DBOPackage -Path MyPackage.zip -ScriptPath .\Scripts -Configuration @{ Database = '#{dbName}'; ConnectionTimeout = 5 }
Install-DBOPackage MyPackage.zip -Variables @{ dbName = 'myDB' }

# Adding builds to the package
Add-DBOBuild Deploy.zip -ScriptPath .\myscripts -Type Unique -Build 2.0
Get-ChildItem .\myscripts | Add-DBOBuild Deploy.zip -Type New,Modified -Build 3.0

# Setting deployment options within the package to be able to deploy it without specifying options
Update-DBOConfig Deploy.zip -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'localhost'; DatabaseName = 'MyDb2' }
Install-DBOPackage Deploy.zip

# Generating config files and using it later as a deployment template
(Get-DBOConfig -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'devInstance'; DatabaseName = 'MyDB' }).SaveToFile('.\dev.json')
(Get-DBOConfig -Path '.\dev.json' -Configuration @{ SqlInstance = 'prodInstance' }).SaveToFile('.\prod.json')
Install-DBOPackage Deploy.zip -ConfigurationFile .\dev.json

# Install package using internal script Deploy.ps1 - useable when module is not installed locally
Expand-Archive Deploy.zip '.\MyTempFolder'
.\MyTempFolder\Deploy.ps1 -SqlInstance server1 -Database MyDB
```

## Planned for future releases

* Code analysis: know what kind of code makes its way into the package. Will find hidden sysadmin grants, USE statements and other undesired statements
* Ready-to-go CI/CD functions
* Support for other RDBMS (eventually, everything that DbUp libraries can talk with)
* Integration with unit tests (tSQLt/Pester/...?)
* Module for Ansible (right now can still be used as a powershell task)
* Linux support
* SQLCMD support
* Deployments to multiple databases at once