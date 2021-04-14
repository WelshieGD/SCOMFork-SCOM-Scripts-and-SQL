﻿<#
Based on 
- https://rlevchenko.com/2018/01/16/automate-scom-2016-installation-with-powershell/
- https://thesystemcenterblog.com/2019/07/08/installing-scom-2019-from-the-command-line/
- https://docs.microsoft.com/en-us/system-center/scom/deploy-install-reporting-server?view=sc-om-2019
- https://redmondmag.com/articles/2020/10/26/sql-server-reporting-for-scom.aspx
- https://blog.aelterman.com/2018/01/01/silent-installation-and-configuration-for-sql-server-2017-reporting-services/
- https://blog.aelterman.com/2018/01/03/complete-automated-configuration-of-sql-server-2017-reporting-services/
- https://www.prajwaldesai.com/install-scom-agent-using-command-line/
#>
# Author: Blake Drumm (v-bldrum@microsoft.com)
# Original Author: Laurent VAN ACKER (lavanack) - https://github.com/lavanack/laurentvanacker.com/blob/master/Windows%20Powershell/SCOM/AutomatedLab%20-%20SCOM%20-%202019.ps1
# Date Created: March 22nd, 2021
# Date Modified: April 14th, 2021
#requires -Version 5 -Modules AutomatedLab -RunAsAdministrator 
trap
{
	Write-Host "Stopping Transcript ..."
	Stop-Transcript
	$VerbosePreference = $PreviousVerbosePreference
	$ErrorActionPreference = $PreviousErrorActionPreference
	[console]::beep(3000, 750)
	Send-ALNotification -Activity 'Lab started' -Message ('Lab deployment failed !') -Provider (Get-LabConfigurationItem -Name Notifications.SubscribedProviders)
}
Clear-Host

Import-Module AutomatedLab
#Clear-LabCache
$PreviousVerbosePreference = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'
#$VerbosePreference = 'Continue'
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$CurrentScript = $MyInvocation.MyCommand.Path
#Getting the current directory (where this script file resides)
$CurrentDir = Split-Path -Path $CurrentScript -Parent
$TranscriptFile = $CurrentScript -replace ".ps1$", "_$("{0:yyyyMMddHHmmss}" -f (Get-Date)).txt"
Start-Transcript -Path $TranscriptFile -IncludeInvocationHeader

#region Global variables definition
$Logon = 'Administrator'
$CustomDomainAdmin = 'bdrumm'
$ClearTextPassword = 'Password1'
$SecurePassword = ConvertTo-SecureString -String $ClearTextPassword -AsPlainText -Force
$NetBiosDomainName = 'CONTOSO'
$FQDNDomainName = 'contoso.com'
#Download SQL : https://go.microsoft.com/fwlink/?linkid=866664
$SQLServerISO = 'SQLServer2019-x64-ENU.iso'

#Disable Windows Defender Realtime Protection - Default: $true
$WindowsDefender_RealtimeDisable = $true

#Currently written to only license DataCenter Evaluation version: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019
#Optional : Without a valid license key you will get a 180-day trial period.
$WindowsProductKey = 'BQYNM-Y3XBC-8PHQH-CWWWX-66RB4'
$SCOMProductKey = 'BXH69-M62YX-QQD6R-3GPWX-8WMFY'
$SQLProductKey = 'P4GHF-Q7T93-JVWND-FR83F-W8H46'
# OU name for placing accounts and groups (Service Accounts,for example)
$OUName = 'Service Accounts'

#SCOM Accounts
$SCOMDataAccessAccount = 'OMDAS'
$SCOMDataWareHouseWriter = 'OMWrite'
$SCOMDataWareHouseReader = 'OMRead'
$SCOMServerAction = 'OMAA'
$SCOMAdmins = 'OMAdmins'
# SCOM management group name (SCOM-2019-MG, for example)
$SCOMMgmtGroup = 'SCOM-2019-MG'


$SQLSVC = 'SQLSVC'
$SQLSSRS = 'SQLSSRS'
# User Name with admin rights on SQL Server (SQLUser,for example)
$SQLUser = 'SQLUser'
$SCOMSetupLocalFolder = "C:\System Center Operations Manager 2019"

#For Microsoft.Windows.Server.2016.Discovery and Microsoft.Windows.Server.Library
#$SCOMWSManagementPackURI = 'https://download.microsoft.com/download/f/7/b/f7b960c9-7392-4c5a-bab4-efbb8a66ec2a/SC%20Management%20Pack%20for%20Windows%20Server%20Operating%20System.msi'
$SCOMWS2016andWS2019ManagementPackURI = 'https://download.microsoft.com/download/D/8/E/D8EB49E9-744E-4F83-B62C-CBBA2B72927C/Microsoft%20System%20Center%20MP%20for%20WS%202016%20and%201709%20Plus.msi'
#More details on http://mpwiki.viacode.com/default.aspx?g=posts&t=218560
$SCOMIISManagementPackURI = 'https://download.microsoft.com/download/4/9/A/49A9DD6B-3ECC-46DD-9115-9DB60C052DA7/Microsoft%20System%20Center%20MP%20for%20IIS%202016%20and%201709%20Plus.msi'
$ReportViewer2015RuntimeURI = 'https://download.microsoft.com/download/A/1/2/A129F694-233C-4C7C-860F-F73139CF2E01/ENU/x86/ReportViewer.msi'
$SystemCLRTypesForSQLServer2014x64URI = 'https://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x64/SQLSysClrTypes.msi'
$SCOMNETAPMManagementPackURI = 'https://download.microsoft.com/download/C/C/2/CC264378-4ADE-4FC3-A6BB-7257CF7D6640/Package/Microsoft.SystemCenter.ApplicationInsights.msi'

#SQL Server 2019 : This will automatically grab the latest SQL Server 2019 Cumulative Update Download URL from the Microsoft Website.
$SQLServer2019LatestCUURI = ((Invoke-WebRequest -Uri "https://www.microsoft.com/en-us/download/confirmation.aspx?id=100809" -UseBasicParsing).Links | Where { $_ -like "*SQLServer2019-KB*-x64.exe*" })[0].href

#SQL Server 2019 Reporting Services : This will automatically grab the latest available SQL Server Reporting Services Download URL from the Microsoft Website.
$SQLServer2019ReportingServicesDownload = ('https://www.microsoft.com/en-us/download/' + ((Invoke-WebRequest -Uri "https://www.microsoft.com/en-us/download/details.aspx?id=100122" -UseBasicParsing).Links | where { $_.href -like "*confirmation*" }).href)
$SQLServer2019ReportingServicesURI = ((Invoke-WebRequest -Uri $SQLServer2019ReportingServicesDownload -UseBasicParsing).Links | Where { $_.class -eq 'mscom-link failoverLink' }).href

$NotepadPlusPlusURI = ((Invoke-WebRequest ('https://notepad-plus-plus.org' + ((Invoke-WebRequest https://notepad-plus-plus.org/ -UseBasicParsing).Links | Where { $_.outerHTML -match 'Current Version' }).href) -UseBasicParsing).Links | Where { $_.href -like "*x64.exe" }).href

#UseDefaultSwitch : Allow you to use a Hyper-V Host System Internet connection for VM Internet Connection
$UseDefaultSwitch = $false
$NetworkID = '192.168.0.0/24'
$DC01IPv4Address = '192.168.0.1'
$GatewayIPv4Address = '192.168.0.2'
$SQL2019IPv4Address = '192.168.0.11'
$SCOM2019WCIPv4Address = '192.168.0.21'
$SCOM2019MS1IPv4Address = '192.168.0.31'
#Redhat 7.9 - if you dont want this deployed, set $DeployRHEL79 = $false.
$DeployRHEL79 = $false
$RHEL79IPv4Address = '192.168.0.58'
#DNS Server Forwarder: for addresses / webpages not in Local Network.
#If $DNSServerForwarder is set to $null, this will be omitted.
$DNSServerForwarder = '10.50.10.50', '10.50.50.50'

$LabName = 'SCOM2019'
#endregion

#Cleaning previously existing lab
if ($LabName -in (Get-Lab -List))
{
	Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue
}

#create an empty lab template and define where the lab XML files and the VMs will be stored
New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV

#make the network definition
Add-LabVirtualNetworkDefinition -Name $LabName -HyperVProperties @{ SwitchType = 'Internal' } -AddressSpace $NetworkID
if ($UseDefaultSwitch)
{
	Add-LabVirtualNetworkDefinition -Name 'Default Switch' -HyperVProperties @{ SwitchType = 'External'; AdapterName = 'NIC1' } -ErrorAction Stop
}

#and the domain definition with the domain admin account
Add-LabDomainDefinition -Name $FQDNDomainName -AdminUser $Logon -AdminPassword $ClearTextPassword

#these credentials are used for connecting to the machines. As this is a lab we use clear-text passwords
Set-LabInstallationCredential -Username $Logon -Password $ClearTextPassword

#defining default parameter values, as these ones are the same for all the machines
$PSDefaultParameterValues = @{
	'Add-LabMachineDefinition:Network'		   = $LabName
	'Add-LabMachineDefinition:DomainName'	   = $FQDNDomainName
	'Add-LabMachineDefinition:DiskSizeInGb'    = 60GB
	'Add-LabMachineDefinition:MinMemory'	   = 2GB
	'Add-LabMachineDefinition:MaxMemory'	   = 4GB
	'Add-LabMachineDefinition:Memory'		   = 4GB
	'Add-LabMachineDefinition:OperatingSystem' = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
	'Add-LabMachineDefinition:Processors'	   = 2
}

#$GatewayIPv4Address = (Get-NetIPInterface | Where{ $_.InterfaceAlias -like '*SCOM2019*' } | Where{ $_.AddressFamily -eq 'IPv4' } | Get-NetIPAddress).IPAddress

$IISAgentNetAdapter = @()
$IISAgentNetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabName -Ipv4Address $SCOM2019WCIPv4Address -Ipv4Gateway $GatewayIPv4Address -Ipv4DNSServers $DC01IPv4Address -RegisterInDNS:$true
if ($UseDefaultSwitch)
{
	$IISAgentNetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp
}
$SQL2019NetAdapter = @()
$SQL2019NetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabName -Ipv4Address $SQL2019IPv4Address -Ipv4Gateway $GatewayIPv4Address -Ipv4DNSServers $DC01IPv4Address -RegisterInDNS:$true
if ($UseDefaultSwitch)
{
	#Adding an Internet Connection on the SQL Server (Required for the SQL Setup via AutomatedLab)
	$SQL2019NetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp
}
$SCOM2019MS1NetAdapter = @()
$SCOM2019MS1NetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabName -Ipv4Address $SCOM2019MS1IPv4Address -Ipv4Gateway $GatewayIPv4Address -Ipv4DNSServers $DC01IPv4Address -RegisterInDNS:$true
if ($UseDefaultSwitch)
{
	#Adding an Internet Connection on the Management Server
	$SCOM2019MS1NetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp
}
if ($DeployRHEL79)
{
	$RHEL79NetAdapter = @()
	$RHEL79NetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabName -Ipv4Address $RHEL79IPv4Address -Ipv4Gateway $GatewayIPv4Address -Ipv4DNSServers $DC01IPv4Address -RegisterInDNS:$true
	if ($UseDefaultSwitch)
	{
		#Adding an Internet Connection on the RHEL 7.9 Machine
		$RHEL79NetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp
	}
}
if ($SQLProductKey)
{
	$SQLServer2019Role = Get-LabMachineRoleDefinition -Role SQLServer2019 -Properties @{
		Features			  = 'SQL,Tools'
		InstanceName		  = 'SCOM2019'
		AgtSvcStartupType	  = 'Automatic'
		BrowserSvcStartupType = 'Automatic'
		NPENABLED			  = '1'
		PID				      = $SQLProductKey
	}
}
else
{
	$SQLServer2019Role = Get-LabMachineRoleDefinition -Role SQLServer2019 -Properties @{
		Features			  = 'SQL,Tools'
		InstanceName		  = 'SCOM2019'
		AgtSvcStartupType	  = 'Automatic'
		BrowserSvcStartupType = 'Automatic'
		NPENABLED			  = '1'
	}
}

Add-LabIsoImageDefinition -Name SQLServer2019 -Path $labSources\ISOs\$SQLServerISO

#region server definitions
#Root Domain controller
Add-LabMachineDefinition -Name DC01 -Roles RootDC -IpAddress $DC01IPv4Address -Gateway $GatewayIPv4Address -DnsServer1 $DC01IPv4Address
#SCOM server
Add-LabMachineDefinition -Name SCOM-2019-MS1 -NetworkAdapter $SCOM2019MS1NetAdapter -Memory 8GB -MinMemory 4GB -MaxMemory 8GB -Processors 4
#SQL Server
Add-LabMachineDefinition -Name SQL-2019 -Roles $SQLServer2019Role -NetworkAdapter $SQL2019NetAdapter -Memory 8GB -MinMemory 8GB -MaxMemory 12GB -Processors 4
#IIS front-end server
Add-LabMachineDefinition -Name IIS-Agent -NetworkAdapter $IISAgentNetAdapter
if ($DeployRHEL79)
{
	Add-LabMachineDefinition -Name RHEL7-9 -NetworkAdapter $RHEL79NetAdapter -Memory 4GB -MinMemory 4GB -MaxMemory 4GB -Processors 2 -OperatingSystem 'Red Hat Enterprise Linux 7.9'
}
#endregion

#Installing servers
Install-Lab

if ($SQLProductKey)
{
	$Drive = Mount-LabIsoImage -ComputerName SQL-2019 -IsoPath $labSources\ISOs\$SQLServerISO -PassThru
	Invoke-LabCommand -ActivityName 'Upgrading SQL 2019 from Evaluation to Full Version.' -ComputerName SQL-2019 -ScriptBlock {
		. "$($Drive.DriveLetter)\setup.exe" '/q' '/IACCEPTSQLSERVERLICENSETERMS' '/ACTION=editionupgrade' '/InstanceName=SCOM2019' "/PID=$SQLProductKey" '/SkipRules=Engine_SqlEngineHealthCheck'
	} -Variable (Get-Variable -Name Drive, SQLProductKey) -PassThru
	Dismount-LabIsoImage -ComputerName SQL-2019
}
#Grab the network adapter names
$network_adapters = (Get-NetAdapter) | Where { $_.Name -match "$LabName" } | Where { $_.InterfaceDescription -match 'Hyper-V Virtual' }

#Set IP for the Internal Network to $GatewayIPv4Address
New-NetIPAddress -InterfaceIndex $network_adapters.ifIndex[0] -IPAddress $GatewayIPv4Address -AddressFamily IPv4 -ErrorAction SilentlyContinue

#Set DNS Server to IPv4 of Domain Controller
Set-DNSClientServerAddress -InterfaceIndex $network_adapters.ifIndex[0] -ServerAddresses $DC01IPv4Address -ErrorAction SilentlyContinue

#endregion

$machines = Get-LabVM | Where { $_.OperatingSystem -match "Windows" }

$Cred = New-Object System.Management.Automation.PSCredential ($Logon, $SecurePassword)

if ($WindowsDefender_RealtimeDisable)
{
	Invoke-LabCommand -UseLocalCredential -ActivityName "Disabling Windows Defender Realtime Protection Component" -ComputerName $machines -ScriptBlock { Set-MpPreference -DisableRealtimeMonitoring $true }
}
#Change from Datacenter Evaluation to Full Version / Register Product Key
if ($WindowsProductKey)
{
	Invoke-LabCommand -UseLocalCredential -ActivityName "Changing from Evaluation to Full Version of Windows Server DataCenter." -ComputerName $machines -ScriptBlock {
		Dism /online /Set-Edition:ServerDatacenter /AcceptEula /ProductKey:$WindowsProductKey /NoRestart /Quiet
	} -Variable (Get-Variable -Name WindowsProductKey) -PassThru
	Restart-LabVM -ComputerName $machines -Wait
}
else
{
	Restart-LabVM -ComputerName SQL-2019 -Wait
}

#Downloading SQL Server 2019 CU8 (or later)
$SQLServer2019LatestCU = Get-LabInternetFile -Uri $SQLServer2019LatestCUURI -Path $labSources\SoftwarePackages -PassThru
#Installing SQL Server 2019 CU8 (or later)
Install-LabSoftwarePackage -ComputerName SQL-2019 -Path $SQLServer2019LatestCU.FullName -CommandLine " /QUIET /IACCEPTSQLSERVERLICENSETERMS /ACTION=PATCH /ALLINSTANCES" #-AsJob
#Get-Job -Name 'Installation of*' | Wait-Job | Out-Null

#region Installing Required Windows Features
Install-LabWindowsFeature -FeatureName Telnet-Client -ComputerName $machines -IncludeManagementTools
#endregion

#Installing and setting up DNS
Invoke-LabCommand -ActivityName 'Domain Naming Service (DNS) & Active Directory Users / Groups (AD) Setup on Domain Controller (DC)' -ComputerName DC01 -ScriptBlock {
	#region DNS management
	#Reverse lookup zone creation
	Add-DnsServerPrimaryZone -NetworkID $NetworkID -ReplicationScope 'Forest' -ErrorAction SilentlyContinue
	
	$ADDistinguishedName = (Get-ADDomain).DistinguishedName
	
	if ($DNSServerForwarder)
	{
		#DNS Forwarder for Domain Controller (This can allow connection to internet)
		Add-DnsServerForwarder -IPAddress $DNSServerForwarder -PassThru -ErrorAction SilentlyContinue | Out-Null
	}
	#Creating AD OU
	$ADOrganizationalUnit = New-ADOrganizationalUnit -Name $OUName -Path $ADDistinguishedName -Passthru -ErrorAction SilentlyContinue
	
	#Creating AD Users
	New-ADUser -Name $CustomDomainAdmin -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -ErrorAction SilentlyContinue
	Add-ADGroupMember -Identity 'Domain Admins' -Members $CustomDomainAdmin -ErrorAction SilentlyContinue
	$group = get-adgroup 'Domain Admins' -properties @("primaryGroupToken") -ErrorAction SilentlyContinue
	get-aduser $CustomDomainAdmin | set-aduser -replace @{ primaryGroupID = $group.primaryGroupToken } -ErrorAction SilentlyContinue
	Remove-ADGroupMember -Identity 'Domain Users' -Members $CustomDomainAdmin -Confirm:$false -ErrorAction SilentlyContinue
	New-ADUser -Name $SQLUser -AccountPassword $SecurePassword -PasswordNeverExpires $true -CannotChangePassword $True -Enabled $true -ErrorAction SilentlyContinue
	New-ADUser -Name $SCOMDataAccessAccount -SamAccountName $SCOMDataAccessAccount -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -Path $ADOrganizationalUnit.DistinguishedName
	New-ADUser -Name $SCOMDataWareHouseReader -SamAccountName $SCOMDataWareHouseReader -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -Path $ADOrganizationalUnit.DistinguishedName
	New-ADUser -Name $SCOMDataWareHouseWriter -SamAccountName $SCOMDataWareHouseWriter -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -Path $ADOrganizationalUnit.DistinguishedName
	New-ADUser -Name $SCOMServerAction -SamAccountName $SCOMServerAction -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -Path $ADOrganizationalUnit.DistinguishedName
	New-ADGroup -Name $SCOMAdmins -GroupScope Global -GroupCategory Security -Path $ADOrganizationalUnit.DistinguishedName
	Add-ADGroupMember $SCOMAdmins $SCOMDataAccessAccount, $SCOMDataWareHouseReader, $SCOMDataWareHouseWriter, $SCOMServerAction
	#SQL Server service accounts (SQLSSRS is a service reporting services account)
	New-ADUser -Name $SQLSVC -SamAccountName $SQLSVC -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -Path $ADOrganizationalUnit.DistinguishedName
	New-ADUser -Name $SQLSSRS -SamAccountName $SQLSSRS -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -Path $ADOrganizationalUnit.DistinguishedName
	Write-Verbose "The service Accounts and SCOM-Admins group have been added to OU=$OUName,$DistinguishedName"
} -Variable (Get-Variable -Name DNSServerForwarder, NetworkID, CustomDomainAdmin, SecurePassword, OUName, SQLUser, SCOMDataAccessAccount, SCOMDataWareHouseReader, SCOMDataWareHouseWriter, SCOMServerAction, SCOMAdmins, SQLSVC, SQLSSRS) -PassThru


Invoke-LabCommand -ActivityName 'Adding the SCOM Admins AD Group to the local Administrators Group' -ComputerName SCOM-2019-MS1, SQL-2019, IIS-Agent -ScriptBlock {
	Add-LocalGroupMember -Member "$NetBiosDomainName\$SCOMAdmins" -Group Administrators
} -Variable (Get-Variable -Name NetBiosDomainName, SCOMAdmins)

Invoke-LabCommand -UseLocalCredential -ActivityName "Disabling IE ESC" -ComputerName $machines -ScriptBlock {
	#Disabling IE ESC
	$AdminKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}'
	$UserKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}'
	Set-ItemProperty -Path $AdminKey -Name 'IsInstalled' -Value 0 -Force -ErrorAction SilentlyContinue
	Set-ItemProperty -Path $UserKey -Name 'IsInstalled' -Value 0 -Force -ErrorAction SilentlyContinue
	Rundll32 iesetup.dll, IEHardenLMSettings
	Rundll32 iesetup.dll, IEHardenUser
	Rundll32 iesetup.dll, IEHardenAdmin
	Remove-Item -Path $AdminKey -Force
	Remove-Item -Path $UserKey -Force
	#Setting the Keyboard to French
	#Set-WinUserLanguageList -LanguageList "fr-FR" -Force
	
	#Renaming the main NIC adapter to Corp
	Rename-NetAdapter -Name "$labName 0" -NewName 'Internal' -PassThru -ErrorAction SilentlyContinue
	Rename-NetAdapter -Name "Ethernet" -NewName 'Internal' -PassThru -ErrorAction SilentlyContinue
	if ($UseDefaultSwitch)
	{
		Rename-NetAdapter -Name "Default Switch 0" -NewName 'Internet' -PassThru -ErrorAction SilentlyContinue
	}
	
} -Variable (Get-Variable -Name UseDefaultSwitch, labName)

Invoke-LabCommand -ActivityName 'Installing IIS, ASP and ASP.NET 4.5+' -ComputerName IIS-Agent -ScriptBlock {
	Install-WindowsFeature Web-Server, Web-Asp, Web-Asp-Net45 -IncludeManagementTools
	Import-Module -Name WebAdministration
	$WebSiteName = 'www.contoso.com'
	#Creating a dedicated application pool
	New-WebAppPool -Name "$WebSiteName" -Force
	#Creating a dedicated web site
	New-WebSite -Name "$WebSiteName" -Port 81 -PhysicalPath "$env:SystemDrive\inetpub\wwwroot" -ApplicationPool "$WebSiteName" -Force
}

#region Install the SQL Powershell Module on SQL Server
##SQL Server Management Studio (SSMS), beginning with version 17.0, doesn't install either PowerShell module. To use PowerShell with SSMS, install the SqlServer module from the PowerShell Gallery.
Write-Host "Downloading Latest SQL Powershell Module from the Powershell Gallery Online."
Get-LabInternetFile https://www.powershellgallery.com/api/v2/package/SqlServer -Path $labSources\SoftwarePackages -File sqlserver_powershell.nupkg
Rename-Item -Path $labSources\SoftwarePackages\sqlserver_powershell.nupkg $labSources\SoftwarePackages\sqlserver_powershell.zip -Force
Expand-Archive $labSources\SoftwarePackages\sqlserver_powershell.zip -DestinationPath $labSources\SoftwarePackages\SqlServer_Powershell
$files_to_remove = $null
$files_to_remove = Get-ChildItem -Directory -Path $labSources\SoftwarePackages\SqlServer_Powershell | Where { $_.Name -match "_rels|package" }
$files_to_remove += Get-ChildItem -Path $labSources\SoftwarePackages\SqlServer_Powershell | Where { $_.Name -eq '[Content_Types].xml' }
$files_to_remove += Get-ChildItem -Path $labSources\SoftwarePackages\SqlServer_Powershell | Where { $_.Name -like "*.nuspec" }
$files_to_remove | Remove-Item -Recurse -Confirm:$false

Copy-LabFileItem -ComputerName SQL-2019 $labSources\SoftwarePackages\SqlServer_Powershell
Remove-Item $labSources\SoftwarePackages\sqlserver_powershell.nupkg, $labSources\SoftwarePackages\sqlserver_powershell.zip -ErrorAction SilentlyContinue
Remove-Item $labSources\SoftwarePackages\SqlServer_Powershell -Recurse -Confirm:$false -ErrorAction SilentlyContinue

Invoke-LabCommand -ActivityName 'Installing the latest SQL Server Powershell Module on SQL-2019 downloaded from Powershell Gallery.' -ComputerName SQL-2019 -ScriptBlock {
	$modules_location = (($env:PSModulePath -split ";") | Where { $_ -like '*Program Files\WindowsPowerShell\Modules' })
	New-Item -Path $modules_location\SqlServer -ItemType Directory -Confirm:$false
	$sql_module_version = ((Get-Content -Path C:\SqlServer_Powershell\SqlServer.psd1 | Where { $_ -match 'ModuleVersion' }).Split("'")[1])
	$new_name = Rename-Item C:\SqlServer_Powershell $sql_module_version
	Move-Item "C:\$sql_module_version" $modules_location\SqlServer
}
#endregion

Invoke-LabCommand -ActivityName "Adding $SQLUser, $CustomDomainAdmin, and $Logon to the SQL SysAdmin Group / Modifying Windows Firewall" -ComputerName SQL-2019 -ScriptBlock {
	
	Import-Module -Name SQLServer
	
	$SQLLogin = Add-SqlLogin -ServerInstance $Env:COMPUTERNAME\$LabName -LoginName "$NetBiosDomainName\$SQLUser" -LoginType "WindowsUser" -Enable
	$SQLLogin.AddToRole("sysadmin")
	
	$SQLLogin = Add-SqlLogin -ServerInstance $Env:COMPUTERNAME\$LabName -LoginName "$NetBiosDomainName\$CustomDomainAdmin" -LoginType "WindowsUser" -Enable
	$SQLLogin.AddToRole("sysadmin")
	
	$SQLLogin = Add-SqlLogin -ServerInstance $Env:COMPUTERNAME\$LabName -LoginName "$NetBiosDomainName\$Logon" -LoginType "WindowsUser" -Enable
	$SQLLogin.AddToRole("sysadmin")
	
	##Setting up some firewall rules
	Set-NetFirewallRule -Name WMI-WINMGMT-In-TCP -Enabled True
	New-NetFirewallRule -Name "SQL DB" -DisplayName "SQL Database" -Profile Domain -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
	New-NetFirewallRule -Name "SQL Server Admin Connection" -DisplayName "SQL Server Admin Connection" -Profile Domain -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
	New-NetFirewallRule -Name "SQL Browser" -DisplayName "SQL Browser" -Profile Domain -Direction Inbound -LocalPort 1434 -Protocol UDP -Action Allow
	New-NetFirewallRule -Name "SQL SRRS (HTTP)" -DisplayName "SQL SRRS (HTTP)" -Profile Domain -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
	New-NetFirewallRule -Name "SQL SRRS (SSL)" -DisplayName "SQL SRRS (SSL)" -Profile Domain -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
	New-NetFirewallRule -Name "SQL Server 445" -DisplayName "SQL Server 445" -Profile Domain -Direction Inbound -LocalPort 445 -Protocol TCP -Action Allow
	New-NetFirewallRule -Name "SQL Server 135" -DisplayName "SQL Server 135" -Profile Domain -Direction Inbound -LocalPort 135 -Protocol TCP -Action Allow
	Write-Verbose "The SQL Server $env:COMPUTERNAME has been configured"
	
	##Starting SQL Server Agent Service (Prerequisite)
	#Set-Service -Name SQLSERVERAGENT -StartupType Automatic -PassThru | Start-Service
} -Variable (Get-Variable -Name CustomDomainAdmin, NetBiosDomainName, SQLUser, Logon, LabName)

# Hastable for getting the ISO Path for every VM (needed for .Net 2.0 setup)
$SCOMServers = Get-LabVM | Where-Object -FilterScript { $_.Name -like "*SCOM*" }
$IsoPathHashTable = $SCOMServers | Select-Object -Property Name, @{ Name = "IsoPath"; Expression = { $_.OperatingSystem.IsoPath } } | Group-Object -Property Name -AsHashTable -AsString
foreach ($CurrentSCOMServer in $SCOMServers.Name)
{
	$Drive = Mount-LabIsoImage -ComputerName $CurrentSCOMServer -IsoPath $IsoPathHashTable[$CurrentSCOMServer].IsoPath -PassThru
	Invoke-LabCommand -ActivityName 'Copying .Net 2.0 cab, lab and demo files locally' -ComputerName $CurrentSCOMServer -ScriptBlock {
		$Sxs = New-Item -Path "C:\Sources\Sxs" -ItemType Directory -Force
		Copy-Item -Path "$($Drive.DriveLetter)\sources\sxs\*" -Destination $Sxs -Recurse -Force
	} -Variable (Get-Variable -Name Drive)
	Dismount-LabIsoImage -ComputerName $CurrentSCOMServer
}

#Region for SCOM Installation
$SystemCLRTypesForSQLServer2014x64 = Get-LabInternetFile -Uri $SystemCLRTypesForSQLServer2014x64URI -Path $labSources\SoftwarePackages -PassThru
Install-LabSoftwarePackage -ComputerName SCOM-2019-MS1 -Path $SystemCLRTypesForSQLServer2014x64.FullName -CommandLine "/qn  /L* $(Join-Path -Path $env:SystemDrive -ChildPath $($SystemCLRTypesForSQLServer2014x64.FileName + ".log")) /norestart ALLUSERS=2"

$ReportViewer2015Runtime = Get-LabInternetFile -Uri $ReportViewer2015RuntimeURI -Path $labSources\SoftwarePackages -PassThru
Install-LabSoftwarePackage -ComputerName SCOM-2019-MS1 -Path $ReportViewer2015Runtime.FullName -CommandLine "/qn /L* $(Join-Path -Path $env:SystemDrive -ChildPath $($ReportViewer2015Runtime.FileName + ".log")) /norestart ALLUSERS=2"

#Get-Job -Name 'Installation of*' | Wait-Job | Out-Null
$LabSourcesLocation = Get-LabSourcesLocation
Install-LabSoftwarePackage -ComputerName SCOM-2019-MS1 -Path "$LabSourcesLocation\SoftwarePackages\SCOM_2019.exe" -CommandLine "/dir=`"$SCOMSetupLocalFolder`" `"/silent`"" -ErrorAction Stop
Invoke-LabCommand -ActivityName 'Installing the Operations Manager Management Server on SCOM-2019-MS1' -ComputerName SCOM-2019-MS1 -ScriptBlock {
	
	#Setting up SCOM Management Server
	$ArgumentList = @(
		"/silent /install /components:OMServer /ManagementGroupName:$SCOMMgmtGroup /SqlServerInstance:SQL-2019\SCOM2019",
		"/DatabaseName:OperationsManager /DWSqlServerInstance:SQL-2019\SCOM2019 /DWDatabaseName:OperationsManagerDW /ActionAccountUser:$NetBiosDomainName\$SCOMServerAction",
		"/ActionAccountPassword:$ClearTextPassword /DASAccountUser:$NetBiosDomainName\$SCOMDataAccessAccount /DASAccountPassword:$ClearTextPassword /DataReaderUser:$NetBiosDomainName\$SCOMDataWareHouseReader",
		"/DataReaderPassword:$ClearTextPassword /DataWriterUser:$NetBiosDomainName\$SCOMDataWareHouseWriter /DataWriterPassword:$ClearTextPassword",
		'/EnableErrorReporting:Always /SendCEIPReports:1 /UseMicrosoftUpdate:0 /AcceptEndUserLicenseAgreement:1'
	)
	#Note: The installation status can also be checked in the SCOM installation log: OpsMgrSetupWizard.log which is found at: %LocalAppData%\SCOM\LOGS
	Start-Process -FilePath "$SCOMSetupLocalFolder\Setup.exe" -ArgumentList $ArgumentList -Wait
	"`"$SCOMSetupLocalFolder\Setup.exe`" $($ArgumentList -join ' ')" | Out-File "$ENV:SystemDrive\SCOMUnattendedSetup.cmd"
	
	if ($SCOMProductKey -match "^\w{5}-\w{5}-\w{5}-\w{5}-\w{5}$")
	{
		#Importing the OperationsManager module by specifying the full folder path
		Import-Module "${env:ProgramFiles}\Microsoft System Center\Operations Manager\Powershell\OperationsManager"
		$Cred = New-Object System.Management.Automation.PSCredential ($(whoami), $SecurePassword)
		#To properly license SCOM, install the product key using the following cmdlet: 
		Set-SCOMLicense -ProductId $SCOMProductKey -ManagementServer $((Get-SCOMManagementServer).DisplayName) -Credential:$Cred -Confirm:$false
		#(Re)Starting the 'System Center Data Access Service'is mandatory to take effect
		Start-Service -DisplayName 'System Center Data Access Service' #-Force
		#Checking the SkuForLicense = Retail 
		Get-SCOMManagementGroup | Format-Table -Property SKUForLicense, Version, TimeOfExpiration -AutoSize
	}
} -PassThru -Variable (Get-Variable -Name SCOMSetupLocalFolder, ClearTextPassword, SecurePassword, SCOMMgmtGroup, NetBiosDomainName, SCOMDataAccessAccount, SCOMDataWareHouseReader, SCOMDataWareHouseWriter, SCOMProductKey, SCOMServerAction)


Invoke-LabCommand -ActivityName 'Installing the Operations Manager Console on SCOM-2019-MS1' -ComputerName SCOM-2019-MS1 -ScriptBlock {
	
	#Setting up SCOM Management Console
	$ArgumentList = @(
		"/silent /install /components:OMConsole /EnableErrorReporting:Always /SendCEIPReports:1 /UseMicrosoftUpdate:0 /AcceptEndUserLicenseAgreement:1"
	)
	#Note: The installation status can also be checked in the SCOM installation log: OpsMgrSetupWizard.log which is found at: %LocalAppData%\SCOM\LOGS
	Start-Process -FilePath "$SCOMSetupLocalFolder\Setup.exe" -ArgumentList $ArgumentList -Wait
	"`"$SCOMSetupLocalFolder\Setup.exe`" $($ArgumentList -join ' ')" | Out-File "$ENV:SystemDrive\SCOMUnattendedSetup.cmd"
	
	Write-Verbose "SCOM Console has been installed. Don't forget to license SCOM"
	
	if ($SCOMProductKey -match "^\w{5}-\w{5}-\w{5}-\w{5}-\w{5}$")
	{
		#Importing the OperationsManager module by specifying the full folder path
		Import-Module "${env:ProgramFiles}\Microsoft System Center\Operations Manager\Powershell\OperationsManager"
		$Cred = New-Object System.Management.Automation.PSCredential ($(whoami), $SecurePassword)
		#To properly license SCOM, install the product key using the following cmdlet: 
		Set-SCOMLicense -ProductId $SCOMProductKey -ManagementServer $((Get-SCOMManagementServer).DisplayName) -Credential:$Cred -Confirm:$false
		#(Re)Starting the 'System Center Data Access Service'is mandatory to take effect
		Start-Service -DisplayName 'System Center Data Access Service' #-Force
		#Checking the SkuForLicense = Retail 
		Get-SCOMManagementGroup | Format-Table -Property SKUForLicense, Version, TimeOfExpiration -AutoSize
	}
} -PassThru -Variable (Get-Variable -Name SCOMSetupLocalFolder, SecurePassword, SCOMProductKey)


Invoke-LabCommand -ActivityName 'Installing the Operations Manager Web Console on SCOM-2019-MS1' -ComputerName SCOM-2019-MS1 -ScriptBlock {
	Install-WindowsFeature Web-Server, Web-Request-Monitor, Web-Asp-Net, Web-Asp-Net45, Web-Windows-Auth, Web-Metabase, NET-WCF-HTTP-Activation45 -IncludeManagementTools -Source "C:\Sources\Sxs"
	Write-Verbose "The Web Console prerequisites have been installed"
	
	#Setting up SCOM Management WebConsole
	$ArgumentList = @(
		"/silent /install /components:OMWebConsole /WebSiteName:""Default Web Site"" /WebConsoleAuthorizationMode:Mixed /SendCEIPReports:1 /UseMicrosoftUpdate:0 /AcceptEndUserLicenseAgreement:1"
	)
	#Note: The installation status can also be checked in the SCOM installation log: OpsMgrSetupWizard.log which is found at: %LocalAppData%\SCOM\LOGS
	Start-Process -FilePath "$SCOMSetupLocalFolder\Setup.exe" -ArgumentList $ArgumentList -Wait
	"`"$SCOMSetupLocalFolder\Setup.exe`" $($ArgumentList -join ' ')" | Out-File "$ENV:SystemDrive\SCOMUnattendedSetup.cmd"
	
	Write-Verbose "SCOM Web Console has been installed. Don't forget to license SCOM"
	
	if ($SCOMProductKey -match "^\w{5}-\w{5}-\w{5}-\w{5}-\w{5}$")
	{
		#Importing the OperationsManager module by specifying the full folder path
		Import-Module "${env:ProgramFiles}\Microsoft System Center\Operations Manager\Powershell\OperationsManager"
		$Cred = New-Object System.Management.Automation.PSCredential ($(whoami), $SecurePassword)
		#To properly license SCOM, install the product key using the following cmdlet: 
		Set-SCOMLicense -ProductId $SCOMProductKey -ManagementServer $((Get-SCOMManagementServer).DisplayName) -Credential:$Cred -Confirm:$false
		#(Re)Starting the 'System Center Data Access Service'is mandatory to take effect
		Start-Service -DisplayName 'System Center Data Access Service' #-Force
		#Checking the SkuForLicense = Retail 
		Get-SCOMManagementGroup | Format-Table -Property SKUForLicense, Version, TimeOfExpiration -AutoSize
	}
} -PassThru -Variable (Get-Variable -Name SCOMSetupLocalFolder, SecurePassword, SCOMProductKey)
#Installing SSRS on the SQL Server
$SQLServer2019ReportingServices = Get-LabInternetFile -Uri $SQLServer2019ReportingServicesURI -Path $labSources\SoftwarePackages -FileName AutomatedLab-SQLSERVER.exe -PassThru
Install-LabSoftwarePackage -ComputerName SQL-2019 -Path $SQLServer2019ReportingServices.FullName -CommandLine " /quiet /IAcceptLicenseTerms /Edition=Eval"
#Get-Job -Name 'Installation of*' | Wait-Job | Out-Null

Invoke-LabCommand -ActivityName 'Configuring Report Server on SQL Server' -ComputerName SQL-2019 -ScriptBlock {
	#From https://blog.aelterman.com/2018/01/01/silent-installation-and-configuration-for-sql-server-2017-reporting-services/
	#Start-Process -FilePath "$env:ProgramFiles\Microsoft SQL Server Reporting Services\Shared Tools\rsconfig.exe" -ArgumentList "-c -s localhost -d ReportServer -a Windows -i SSRS" -Wait
	# "$env:ProgramFiles\Microsoft SQL Server Reporting Services\Shared Tools\rsconfig.exe -c -s localhost -d ReportServer -a Windows -i SSRS" | Out-File "$ENV:SystemDrive\SCOMUnattendedSetup.cmd" -Append
	
	#From (with modifications) https://blog.aelterman.com/2018/01/03/complete-automated-configuration-of-sql-server-2017-reporting-services/
	#From https://gist.github.com/SvenAelterman/f2fd058bf3a8aa6f37ac69e5d5dd2511
	
	function Get-ConfigSet()
	{
		return Get-WmiObject -namespace "root\Microsoft\SqlServer\ReportServer\RS_SSRS\v15\Admin" -class MSReportServer_ConfigurationSetting -ComputerName localhost
	}
	
	# Allow importing of sqlps module
	Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
	
	# Retrieve the current configuration
	$configset = Get-ConfigSet
	
	$configset
	
	If (! $configset.IsInitialized)
	{
		# Get the ReportServer and ReportServerTempDB creation script
		[string]$dbscript = $configset.GenerateDatabaseCreationScript("ReportServer", 1033, $false).Script
		
		# Import the SQL Server PowerShell module
		#Import-Module sqlps -DisableNameChecking | Out-Null
		
		# Establish a connection to the database server (localhost)
		$conn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $env:ComputerName
		$conn.ApplicationName = "SSRS Configuration Script"
		$conn.StatementTimeout = 0
		$conn.Connect()
		$smo = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $conn
		
		# Create the ReportServer and ReportServerTempDB databases
		$db = $smo.Databases["master"]
		$db.ExecuteNonQuery($dbscript)
		
		# Set permissions for the databases
		$dbscript = $configset.GenerateDatabaseRightsScript($configset.WindowsServiceIdentityConfigured, "ReportServer", $false, $true).Script
		$db.ExecuteNonQuery($dbscript)
		
		# Set the database connection info
		$configset.SetDatabaseConnection("(local)", "ReportServer", 2, "", "")
		
		$configset.SetVirtualDirectory("ReportServerWebService", "ReportServer", 1033)
		$configset.ReserveURL("ReportServerWebService", "http://+:80", 1033)
		
		# For SSRS 2016-2017 only, older versions have a different name
		$configset.SetVirtualDirectory("ReportServerWebApp", "Reports", 1033)
		$configset.ReserveURL("ReportServerWebApp", "http://+:80", 1033)
		try
		{
			$configset.InitializeReportServer($configset.InstallationID)
		}
		catch
		{
			throw (New-Object System.Exception("Failed to Initialize Report Server $($_.Exception.Message)", $_.Exception))
		}
		
		# Re-start services?
		$configset.SetServiceState($false, $false, $false)
		Restart-Service $configset.ServiceName
		$configset.SetServiceState($true, $true, $true)
		
		# Update the current configuration
		$configset = Get-ConfigSet
		
		# Output to screen
		$configset.IsReportManagerEnabled
		$configset.IsInitialized
		$configset.IsWebServiceEnabled
		$configset.IsWindowsServiceEnabled
		$configset.ListReportServersInDatabase()
		$configset.ListReservedUrls();
		
		$inst = Get-WmiObject -namespace "root\Microsoft\SqlServer\ReportServer\RS_SSRS\v15" -class MSReportServer_Instance -ComputerName localhost
		
		$inst.GetReportServerUrls()
	}
	
}

Install-LabSoftwarePackage -ComputerName SQL-2019 -Path "$LabSourcesLocation\SoftwarePackages\SCOM_2019.exe" -CommandLine "/dir=`"$SCOMSetupLocalFolder`" `"/silent`"" -ErrorAction Stop
Invoke-LabCommand -ActivityName 'Installing the Operations Manager Reporting on the SQL Server' -ComputerName SQL-2019 -ScriptBlock {
	#Setting up SCOM
	$ArgumentList = @(
		"/silent /install /components:OMReporting /ManagementServer:SCOM-2019-MS1 /SRSInstance:SQL-2019\SSRS",
		"/DataReaderUser:$NetBiosDomainName\$SCOMDataWareHouseReader /DataReaderPassword:$ClearTextPassword",
		"/SendODRReports:1 /UseMicrosoftUpdate:0 /AcceptEndUserLicenseAgreement:1"
	)
	#Note: The installation status can also be checked in the SCOM installation log: OpsMgrSetupWizard.log which is found at: %LocalAppData%\SCOM\LOGS
	Start-Process -FilePath "$SCOMSetupLocalFolder\Setup.exe" -ArgumentList $ArgumentList -Wait
	"`"$SCOMSetupLocalFolder\Setup.exe`" $($ArgumentList -join ' ')" | Out-File "$ENV:SystemDrive\SCOMUnattendedSetup.cmd"
} -Variable (Get-Variable -Name SCOMSetupLocalFolder, ClearTextPassword, NetBiosDomainName, SCOMDataWareHouseReader)
Dismount-LabIsoImage -ComputerName SQL-2019


Invoke-LabCommand -ActivityName 'Cleanup on SQL Server' -ComputerName SQL-2019 -ScriptBlock {
	Remove-Item -Path "C:\vcredist_x*.*" -Force
	Remove-Item -Path "C:\SSMS-Setup-ENU.exe" -Force
	#Disabling the Internet Connection on the SQL Server
	#Get-NetAdapter -Name Internet | Disable-NetAdapter -Confirm:$false
}


#Downloading the SCOM IIS and dependent Management Packs
$SCOMIISManagementPack = Get-LabInternetFile -Uri $SCOMIISManagementPackURI -Path $labSources\SoftwarePackages -PassThru
#$SCOMWSManagementPack = Get-LabInternetFile -Uri $SCOMWSManagementPackURI -Path $labSources\SoftwarePackages -PassThru
$SCOMWS2016andWS2019ManagementPack = Get-LabInternetFile -Uri $SCOMWS2016andWS2019ManagementPackURI -Path $labSources\SoftwarePackages -PassThru
$SCOMNETAPMManagementPack = Get-LabInternetFile -Uri $SCOMNETAPMManagementPackURI -Path $labSources\SoftwarePackages -PassThru

#Installing the SCOM IIS and Dependent Management Packs
#Install-LabSoftwarePackage -ComputerName SCOM-2019-MS1 -Path $SCOMWSManagementPack.FullName -CommandLine "-quiet"
Install-LabSoftwarePackage -ComputerName SCOM-2019-MS1 -Path $SCOMWS2016andWS2019ManagementPack.FullName -CommandLine "-quiet"
Install-LabSoftwarePackage -ComputerName SCOM-2019-MS1 -Path $SCOMIISManagementPack.FullName -CommandLine "-quiet"
Install-LabSoftwarePackage -ComputerName SCOM-2019-MS1 -Path $SCOMNETAPMManagementPack.FullName -CommandLine "-quiet"
#Get-Job -Name 'Installation of*' | Wait-Job | Out-Null

Invoke-LabCommand -ActivityName 'Installing Management Packs' -ComputerName SCOM-2019-MS1 -ScriptBlock {
	# From GutHub : Script designed to enumerate and download currently available MPs from Microsoft Download servers.
	#Invoke-Expression -Command "& { $(Invoke-RestMethod https://raw.githubusercontent.com/slavizh/Get-SCOMManagementPacks/master/Get-SCOMManagementPacks.ps1) } -Extract"
	#For some cleanup in case of a previous install
	#'Microsoft.SystemCenter.ApplicationInsights', 'Microsoft.Windows.InternetInformationServices.2016', 'Microsoft.Windows.InternetInformationServices.CommonLibrary','Microsoft.Windows.Server.2016.Discovery', 'Microsoft.Windows.Server.Library' | Get-SCOMManagementPack | Remove-SCOMManagementPack
	#Installing Windows Server Management Pack prior IIS
	#Importing the OperationsManager module by specifying the full folder path
	Import-Module "${env:ProgramFiles}\Microsoft System Center\Operations Manager\Powershell\OperationsManager"
	& "$env:ProgramFiles\Microsoft System Center\Operations Manager\Powershell\OperationsManager\Functions.ps1"
	& "$env:ProgramFiles\Microsoft System Center\Operations Manager\Powershell\OperationsManager\Startup.ps1"
	Get-ChildItem -Path "${env:ProgramFiles(x86)}\System Center Management Packs\" -File -Filter *.mp? -Recurse | Where-Object -FilterScript { $_.BaseName -in 'Microsoft.Windows.Server.Library' } | Import-SCOMManagementPack
	Get-ChildItem -Path "${env:ProgramFiles(x86)}\System Center Management Packs\" -File -Filter *.mp? -Recurse | Where-Object -FilterScript { $_.BaseName -in 'Microsoft.Windows.Server.2016.Discovery' } | Import-SCOMManagementPack
	#Installing the Reports and Monitoring Management Pack
	Get-ChildItem -Path "${env:ProgramFiles(x86)}\System Center Management Packs\" -File -Filter *.mp? -Recurse | Where-Object -FilterScript { $_.BaseName -in 'Microsoft.Windows.Server.Reports' } | Import-SCOMManagementPack
	Get-ChildItem -Path "${env:ProgramFiles(x86)}\System Center Management Packs\" -File -Filter *.mp? -Recurse | Where-Object -FilterScript { $_.BaseName -in 'Microsoft.Windows.Server.2016.Monitoring' } | Import-SCOMManagementPack
	#Installing IIS Management Pack.
	Get-ChildItem -Path "${env:ProgramFiles(x86)}\System Center Management Packs\" -File -Filter *.mp? -Recurse | Where-Object -FilterScript { $_.BaseName -in 'Microsoft.Windows.InternetInformationServices.CommonLibrary' } | Import-SCOMManagementPack
	Get-ChildItem -Path "${env:ProgramFiles(x86)}\System Center Management Packs\" -File -Filter *.mp? -Recurse | Where-Object -FilterScript { $_.BaseName -in 'Microsoft.Windows.InternetInformationServices.2016' } | Import-SCOMManagementPack
	#Installing ApplicationInsights ManagementPack.
	Get-ChildItem -Path "${env:ProgramFiles(x86)}\System Center Management Packs\" -File -Filter *.mp? -Recurse | Where-Object -FilterScript { $_.BaseName -in 'Microsoft.SystemCenter.ApplicationInsights' } | Import-SCOMManagementPack
	
	$SCOMAgent = Install-SCOMAgent -PrimaryManagementServer $(Get-SCOMManagementServer) -DNSHostName IIS-Agent.contoso.com -PassThru
	Get-SCOMPendingManagement | Approve-SCOMPendingManagement
}

$NotepadPlusPlusLocation = Get-LabInternetFile -URI $NotepadPlusPlusURI -Path $labSources\SoftwarePackages -Passthru
Install-LabSoftwarePackage -ComputerName $machines -Path $NotepadPlusPlusLocation.FullName -CommandLine "/S"

#endregion
if ($UseDefaultSwitch)
{
	#Removing the Internet Connection on the SQL Server (Required only for the SQL Setup via AutomatedLab)
	Get-VM -Name 'SQL-2019' | Remove-VMNetworkAdapter -Name 'Default Switch' -ErrorAction SilentlyContinue
}

#Setting processor number to 1 for all VMs (The AL deployment fails with 1 CPU)
#Get-LabVM -All | Stop-VM -Passthru -Force | Set-VMProcessor -Count 1
Start-LabVm -All -ProgressIndicator 1 -Wait

Checkpoint-LabVM -SnapshotName 'FullInstall' -All

Show-LabDeploymentSummary -Detailed

$VerbosePreference = $PreviousVerbosePreference
$ErrorActionPreference = $PreviousErrorActionPreference
#Restore-LabVMSnapshot -SnapshotName 'FullInstall' -All

Stop-Transcript
