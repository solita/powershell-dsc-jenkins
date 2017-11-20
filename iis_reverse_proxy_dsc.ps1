# Use the install-modules to first needed dsc resources
Configuration IIS_REVERSE_PROXY
{
	param (
		$ThumbPrint,
		$InstallConfDirectory = "./",
		$JenkinsPort = 8080
    )
	Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xWebAdministration'
	Import-DscResource -ModuleName 'cChoco'
    Node $AllNodes.NodeName {
		# Check the windowsfeature names with Get-WindowsFeature
		# Install .NET 3.5
        WindowsFeature NetFrameworkCore 
        {
            Ensure    = "Present" 
            Name      = "NET-Framework-Core"
        }
        # Install Chocolatey
        cChocoInstaller installChoco
        {
            InstallDir = "c:\choco"
            DependsOn = "[WindowsFeature]NetFrameworkCore"
        }
		# Install the IIS role
        WindowsFeature IIS
        {
            Ensure          = "Present"
            Name            = "Web-Server"
        }
        # Install the ASP .NET 4.5 role
        WindowsFeature AspNet45
        {
            Ensure          = "Present"
            Name            = "Web-Asp-Net45"
        }
		# Install the web management console
        WindowsFeature WebManagementConsole
        {
            Ensure          = "Present"
            Name            = "Web-Mgmt-Console"
			DependsOn 		= "[WindowsFeature]IIS"
        }
		# Install the web management console
        WindowsFeature LoggingTools
        {
            Ensure          = "Present"
            Name            = "Web-Custom-Logging"
			DependsOn 		= "[WindowsFeature]IIS"
        }
		# Install the web management console
        WindowsFeature CustomLogging
        {
            Ensure          = "Present"
            Name            = "Web-Log-Libraries"
			DependsOn 		= "[WindowsFeature]IIS"
        }
		# Install the web management console
        WindowsFeature Tracing
        {
            Ensure          = "Present"
            Name            = "Web-Http-Tracing"
			DependsOn 		= "[WindowsFeature]IIS"
        }
		# Make sure to get rid of default web site
        xWebsite DefaultWebSite
        {
            Ensure          = "Absent"
            Name            = "Default Web Site"
            State           = "Stopped"
            PhysicalPath    = "C:\inetpub\wwwroot"
            DependsOn = "[WindowsFeature]AspNet45","[WindowsFeature]IIS"
        }
		File JenkinsProxyFolder 
		{
			DestinationPath = "C:\inetpub\JenkinsProxy\index.html"
			SourcePath = (Join-Path $InstallConfDirectory "index.html")
			Ensure = "Present"
			Type = "File"
			Checksum = "modifiedDate"
			Force = $true
			MatchSource = $true
		}
		# Create jenkins proxywebsite
		xWebsite JenkinsProxyWebSite
        {
            Ensure          = "Present"
            Name            = "JenkinsProxyWebSite"
            State           = "Started"
            PhysicalPath    = "C:\inetpub\JenkinsProxy"
            BindingInfo     = @(
                MSFT_xWebBindingInformation
                {
                    Protocol              = "HTTPS"
                    Port                  = 443
                    CertificateThumbprint = $thumbPrint
                    CertificateStoreName  = "My"
                }
            )
            DependsOn = "[WindowsFeature]AspNet45","[WindowsFeature]IIS","[File]JenkinsProxyFolder"
        }
        # Install UrlRewrite
        cChocoPackageInstaller UrlRewrite
        {
            Name = "urlrewrite"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		# Install UrlRewrite
        cChocoPackageInstaller ApplicationRequestRouting
        {
            Name = "iis-arr"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		Script ReWriteRules
		{
			#Adds rewrite allowedServerVariables to applicationHost.config
			DependsOn = "[cChocoPackageInstaller]UrlRewrite"
			SetScript = {
				$current = Get-WebConfiguration /system.webServer/rewrite/allowedServerVariables | select -ExpandProperty collection | ?{$_.ElementTagName -eq "add"} | select -ExpandProperty name
				$expected = @("HTTPS", "HTTP_X_FORWARDED_FOR", "HTTP_X_FORWARDED_PROTO", "REMOTE_ADDR")
				$missing = $expected | where {$current -notcontains $_}
				try
				{
					Start-WebCommitDelay 
					$missing | %{ Add-WebConfiguration /system.webServer/rewrite/allowedServerVariables -atIndex 0 -value @{name="$_"} -Verbose }
					Stop-WebCommitDelay -Commit $true 
				} 
				catch [System.Exception]
				{ 
					$_ | Out-String
				}
			}
			TestScript = {
				$current = Get-WebConfiguration /system.webServer/rewrite/allowedServerVariables | select -ExpandProperty collection | select -ExpandProperty name
				$expected = @("HTTPS", "HTTP_X_FORWARDED_FOR", "HTTP_X_FORWARDED_PROTO", "REMOTE_ADDR")
				$result = -not @($expected| where {$current -notcontains $_}| select -first 1).Count
				return $result
			}
			GetScript = {
				$allowedServerVariables = Get-WebConfiguration /system.webServer/rewrite/allowedServerVariables | select -ExpandProperty collection
				return $allowedServerVariables
			}
		}
		Script HTTPToHTTPS
		{
			DependsOn = "[cChocoPackageInstaller]UrlRewrite"
			SetScript = {
				$Name = "HTTP to HTTPS Redirect"
				$PsPath = "MACHINE/WEBROOT/APPHOST"
				$Filter = "system.webserver/rewrite/GlobalRules"

				Clear-WebConfiguration -pspath $PsPath -filter "$Filter/rule[@name='$Name']"
				if ($Site) {
					$Filter = "system.webserver/rewrite/rules"
					Clear-WebConfiguration -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']"
				}

				Add-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter" -name "." -value @{name=$Name; patternSyntax='ECMAScript'; stopProcessing='True'}
				Set-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/match" -name url -value "(.*)"
				Add-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/conditions" -name "." -value @{input="{HTTPS}"; pattern='^OFF$'}
				if ($EnableProxyRules -eq "true") {
					Add-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/conditions" -name "." -value @{input="{HTTP_X_FORWARDED_PROTO}"; pattern='^HTTP$'}
				}

				Set-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/action" -name "type" -value "Redirect"
				Set-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/action" -name "url" -value "https://{HTTP_HOST}/{R:1}"
				Set-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/action" -name "redirectType" -value "Permanent" 
			}
			TestScript = {
				$current = Get-WebConfiguration /system.webServer/rewrite/rules | select -ExpandProperty collection | select -ExpandProperty name
				$expected = @("HTTP to HTTPS Redirect")
				$result = -not @($expected| where {$current -notcontains $_}| select -first 1).Count
				return $result
			}
			GetScript = {
				$rules = Get-WebConfiguration /system.webServer/rewrite/rules | select -ExpandProperty collection
				return $rules
			}
		}
		Script JenkinsReverseProxy
		{
			DependsOn = "[cChocoPackageInstaller]UrlRewrite","[cChocoPackageInstaller]ApplicationRequestRouting"
			SetScript = {
				$Name = "HTTPS Reverse Proxy to Jenkins"
				$proxyTargetPath = ("http://localhost:"+$Using:JenkinsPort+"/{R:0}")

				Clear-WebConfiguration -pspath $PsPath -filter "$Filter/rule[@name='$Name']"
				$Filter = "system.webserver/rewrite/rules"
				Clear-WebConfiguration -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']"
				Add-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter" -name "." -value @{name=$Name; patternSyntax='ECMAScript'; stopProcessing='True'}
				Set-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/match" -name url -value "(.*)"
				Set-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/action" -name "type" -value "Rewrite"
				# R:0 Is full phase, R:1 Is the domain with the port and R:2 is the querypart
				Set-WebConfigurationProperty -location $Site -pspath $PsPath -filter "$Filter/rule[@name='$Name']/action" -name "url" -value $proxyTargetPath
			}
			TestScript = {
				$current = Get-WebConfiguration /system.webServer/rewrite/rules | select -ExpandProperty collection | select -ExpandProperty name
				$expected = @("HTTPS to Jenkins")
				$result = -not @($expected| where {$current -notcontains $_}| select -first 1).Count
				return $result
			}
			GetScript = {
				$rules = Get-WebConfiguration /system.webServer/rewrite/rules | select -ExpandProperty collection
				return $rules
			}
		}
		Script EnableARRProxy
		{
		DependsOn = "[WindowsFeature]WebManagementConsole","[WindowsFeature]IIS","[cChocoPackageInstaller]UrlRewrite","[cChocoPackageInstaller]ApplicationRequestRouting"
			SetScript = {
				$assembly = [System.Reflection.Assembly]::LoadFrom("$env:systemroot\system32\inetsrv\Microsoft.Web.Administration.dll")
				$manager = new-object Microsoft.Web.Administration.ServerManager
				$sectionGroupConfig = $manager.GetApplicationHostConfiguration()

				$sectionName = 'proxy';

				$webserver = $sectionGroupConfig.RootSectionGroup.SectionGroups['system.webServer'];
				if (!$webserver.Sections[$sectionName])
				{
					$proxySection = $webserver.Sections.Add($sectionName);
					$proxySection.OverrideModeDefault = "Deny";
					$proxySection.AllowDefinition="AppHostOnly";
					$manager.CommitChanges();
				}

				$manager = new-object Microsoft.Web.Administration.ServerManager
				$config = $manager.GetApplicationHostConfiguration()
				$section = $config.GetSection('system.webServer/' + $sectionName)
				$enabled = $section.GetAttributeValue('enabled');
				$section.SetAttributeValue('enabled', 'true');
				$manager.CommitChanges();
			}
			TestScript = {
				$assembly = [System.Reflection.Assembly]::LoadFrom("$env:systemroot\system32\inetsrv\Microsoft.Web.Administration.dll")
				$sectionName = 'proxy';
				$manager = new-object Microsoft.Web.Administration.ServerManager
				$sectionGroupConfig = $manager.GetApplicationHostConfiguration()
				$config = $manager.GetApplicationHostConfiguration()
				$section = $config.GetSection('system.webServer/' + $sectionName)
				return ($section -eq $null -and $section.GetAttributeValue('enabled') -eq $False)
			}
			GetScript = {
				$assembly = [System.Reflection.Assembly]::LoadFrom("$env:systemroot\system32\inetsrv\Microsoft.Web.Administration.dll")
				$sectionName = 'proxy';
				$manager = new-object Microsoft.Web.Administration.ServerManager
				$sectionGroupConfig = $manager.GetApplicationHostConfiguration()
				$config = $manager.GetApplicationHostConfiguration()
				$section = $config.GetSection('system.webServer/' + $sectionName)
				return $section.GetAttributeValue('enabled')
			}
		}
   }
}

$ConfigData = @{
    AllNodes = 
    @(
        @{
            NodeName = "LocalHost"
        }
    )
}
$thumbPrint = Read-Host "What is your certificate thumbprint?"
$thumb = Get-ChildItem cert:\localmachine\my | Where { $_.Thumbprint -like $thumbPrint }| Select Thumbprint
if($thumb -eq $NULL) 
{
	$certificatePath = Read-Host "Did not found certificate, what is path to your pfx?"
	$mypwd = Read-Host -AsSecureString "What is password for your certificate?"
	Import-PfxCertificate -FilePath $certificatePath cert:\localMachine\my -Password $mypwd
}
$currentPath = (split-path -parent $MyInvocation.MyCommand.Definition)
$installConfPath = (join-path $currentPath "misc")
IIS_REVERSE_PROXY -ThumbPrint $thumbPrint -InstallConfDirectory $installConfPath -JenkinsPort 8080 -ConfigurationData $ConfigData
Start-DscConfiguration -Path .\IIS_REVERSE_PROXY -Wait -Verbose -Force