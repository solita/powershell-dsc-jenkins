# Use the install-modules to first needed dsc resources
Configuration JENKINS_CI
{
    param (
        $JenkinsPort = 8080,
		$JenkinsPlugins = @{},
		$JenkinsUsername = "",
		$JenkinsPassword = "",
		$JenkinsXmx = 1024,
		$JenkinsMaxPermSize = 128,
		$InstallConfDirectory = "./",
		$JenkinsInitScriptPath = "",
		$JenkinsUsernameTemplate = "",
		$JenkinsPasswordTemplate = ""
    )
	# Reference https://dscottraynsford.wordpress.com/2016/04/18/install-jenkins-using-dsc-part-2/
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'cChoco'
    Import-DscResource -ModuleName 'xNetworking'
	
    Node $AllNodes.NodeName {
        
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

        # Install JDK8
        cChocoPackageInstaller installJdk8
        {
            Name = "jdk8"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		# Install Visual Studio, todo: optional features (F#) with param --includeOptional
		cChocoPackageInstaller installVisualStudio
        {
            Name = "visualstudio2017professional"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		# Install Visual Studio Azure tools 
		<#cChocoPackageInstaller installVisualStudioAzureWorkload
        {
            Name = "visualstudio2017-workload-azure"
            DependsOn = "[cChocoInstaller]installChoco","[cChocoPackageInstaller]installVisualStudio"
        }#>
		
		# Install Visual Studio Web tools 
		cChocoPackageInstaller installVisualStudioWebWorkload
        {
            Name = "visualstudio2017-workload-netweb"
			Params = "--includeOptional"
            DependsOn = "[cChocoInstaller]installChoco","[cChocoPackageInstaller]installVisualStudio"
        }
		
		# Install Visual studio Data tools 
		cChocoPackageInstaller installVisualStudioDataWorkload
        {
            Name = "visualstudio2017-workload-data"
            DependsOn = "[cChocoInstaller]installChoco","[cChocoPackageInstaller]installVisualStudio"
        }
		
		# Install Visual studio Data tools 
		cChocoPackageInstaller installNotepadplusplus
        {
            Name = "notepadplusplus"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		# Install nodejs
		cChocoPackageInstaller installNodejs
        {
            Name = "nodejs.install"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		cChocoPackageInstaller installPython
        {
            Name = "python2"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		# Install nodejs
		cChocoPackageInstaller installFirefox
        {
            Name = "firefox"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		# Install Git
		cChocoPackageInstaller installGit
        {
            Name = "git.install"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		# Install Zap
		cChocoPackageInstaller installZap
        {
            Name = "zap"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		# Install NuGet
		File installNuget 
		{
			DestinationPath = "C:\tools\nuget\nuget.exe"
			SourcePath = (Join-Path $InstallConfDirectory "nuget.exe")
			Ensure = "Present"
			Type = "File"
			Checksum = "modifiedDate"
			Force = $true
			MatchSource = $true
		}
		
		# Install powershell-zap module 		
		Script installPowershellZap 
		{
			GetScript = {
				return @{ Result = gci "C:\tools\powershell-zap-master" }
			}
			SetScript = {
				mkdir "C:\tools\powershell-zap-master"
				$gitexe = "${ENV:ProgramFiles}\Git\cmd\git.exe"
				$arguments = 'clone https://github.com/solita/powershell-zap.git "C:\tools\powershell-zap-master"'
				$null = start-process $gitexe $arguments 
			}
			TestScript = {
				Return (Test-Path "C:\tools\powershell-zap-master")
			}
			DependsOn = "[cChocoPackageInstaller]installJdk8","[cChocoPackageInstaller]installGit" 
		}
		
		Script installJmeterPerfortrator 
		{
			GetScript = {
				return @{ Result = gci "C:\tools\jmeter-perfotrator-master" }
			}
			SetScript = {
				mkdir "C:\tools\jmeter-perfotrator-master"
				$gitexe = "${ENV:ProgramFiles}\Git\cmd\git.exe"
				$arguments = 'clone https://github.com/solita/jmeter-perfotrator.git "C:\tools\jmeter-perfotrator-master"'
				$null = start-process $gitexe $arguments 
			}
			TestScript = {
				Return (Test-Path "C:\tools\jmeter-perfotrator-master")
			}
			DependsOn = "[cChocoPackageInstaller]installJdk8","[cChocoPackageInstaller]installGit" 
		}
		
		# There can be only one "environment path variable setting", use script for others
		Environment setVS2017ToolsPath 
		{
			Name = 'PATH'
			Ensure = 'Present'
			Path = $true
			DependsOn = "[cChocoPackageInstaller]installVisualStudio"
			Value = "${ENV:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\Common7\IDE"
		} 
		
		# Set Java to path
		Script SetJavaToPath 
		{
			GetScript = {
				return @{ Result = $env:Path }
			}
			SetScript = {
				# Try to find Java bin path and force the result to string 
				[string]$javaBinPath = gci "${Env:ProgramFiles}\Java" -r -filter java.exe | Select Directory | Select-Object -first 1 | % { $_.Directory.FullName }
				# Adds javaBinPath to path variable 
				$newPathValue = $env:Path + ";"+$javaBinPath
				# You might need to reset your console after this 
				[Environment]::SetEnvironmentVariable("Path", $newPathValue, [EnvironmentVariableTarget]::Machine)
				# Add also path to current session
				$env:Path = $newPathValue
			}
			TestScript = {
				# Try to find Java bin path and force the result to string 
				[string]$javaBinPath = gci "${Env:ProgramFiles}\Java" -r -filter java.exe | Select Directory | Select-Object -first 1 | % { $_.Directory.FullName }
				if(-not $env:Path.Contains($javaBinPath))
				{
					# Do update
					Return $False
				}
				# Don't update
				Return $True
			}
			DependsOn = "[cChocoPackageInstaller]installJdk8"
		}
		
		# Set MsBuild to path
		Script SetMsbuildToPath 
		{
			GetScript = {
				return @{ Result = $env:Path }
			}
			SetScript = {
				# Try to find Git bin path and force the result to string 
				[string]$binPath = "${ENV:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\MSBuild\15.0\Bin"
				# Adds binPath to path variable 
				$newPathValue = $env:Path + ";"+$binPath
				# You might need to reset your console after this 
				[Environment]::SetEnvironmentVariable("Path", $newPathValue, [EnvironmentVariableTarget]::Machine)
				# Add also path to current session
				$env:Path = $newPathValue
			}
			TestScript = {
				# Try to find Git bin path and force the result to string 
				[string]$binPath = "${ENV:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\MSBuild\15.0\Bin"
				if(-not $env:Path.Contains($binPath))
				{
					# Do update
					Return $False
				}
				# Don't update
				Return $True
			}
			DependsOn = "[cChocoPackageInstaller]installVisualStudio"
		}
		
		Script SetFxCopToPath
		{
			GetScript = {
				return @{ Result = $env:Path }
			}
			SetScript = {
				# Try to find Git bin path and force the result to string 
				[string]$binPath = "${ENV:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\Team Tools\Static Analysis Tools\FxCop"
				# Adds binPath to path variable 
				$newPathValue = $env:Path + ";"+$binPath
				# You might need to reset your console after this 
				[Environment]::SetEnvironmentVariable("Path", $newPathValue, [EnvironmentVariableTarget]::Machine)
				# Add also path to current session
				$env:Path = $newPathValue
			}
			TestScript = {
				# Try to find Git bin path and force the result to string 
				[string]$binPath = "${ENV:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\Team Tools\Static Analysis Tools\FxCop"
				if(-not $env:Path.Contains($binPath))
				{
					# Do update
					Return $False
				}
				# Don't update
				Return $True
			}
			DependsOn = "[cChocoPackageInstaller]installVisualStudio"
		}
		
		# Set NuGet to path
		Script SetNugetToPath 
		{
			GetScript = {
				return @{ Result = $env:Path }
			}
			SetScript = {
				# Try to find Git bin path and force the result to string 
				[string]$binPath = "C:\tools\nuget"
				# Adds binPath to path variable 
				$newPathValue = $env:Path + ";"+$binPath
				# You might need to reset your console after this 
				[Environment]::SetEnvironmentVariable("Path", $newPathValue, [EnvironmentVariableTarget]::Machine)
				# Add also path to current session
				$env:Path = $newPathValue
			}
			TestScript = {
				# Try to find Git bin path and force the result to string 
				[string]$binPath = "C:\tools\nuget"
				if(-not $env:Path.Contains($binPath))
				{
					# Do update
					Return $False
				}
				# Don't update
				Return $True
			}
			DependsOn = "[File]installNuget"
		}
		
        # Install Jenkins
        cChocoPackageInstaller installJenkins
        {
            Name = "Jenkins"
            DependsOn = "[cChocoInstaller]installChoco"
        }
		
		Script SetJenkinsServiceArguments
        {
            SetScript = {
				$argString = "-Xrs -Xmx"+$Using:JenkinsXmx+"m -XX:MaxPermSize="+$Using:JenkinsMaxPermSize+"m -Djenkins.install.runSetupWizard=false -Dhudson.lifecycle=hudson.lifecycle.WindowsServiceLifecycle -jar `"%BASE%\jenkins.war`" --httpPort="+$Using:JenkinsPort+" --webroot=`"%BASE%\war`""
                Write-Verbose -Verbose "Setting jenkins service arguments to $argString"
				
                $Config = Get-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml"
                $NewConfig = $Config `
                    -replace '<arguments>[\s\S]*?<\/arguments>',"<arguments>${argString}</arguments>"
                Set-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml" `
                    -Value $NewConfig `
                    -Force
                Write-Verbose -Verbose "Restarting Jenkins"
            }
            GetScript = {
                $Config = Get-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml"
                $Matches = @([regex]::matches($Config, "<arguments>[\s\S]*?<\/arguments>", 'IgnoreCase'))
                $currentMatch = $Matches.Groups[1].Value
                Return @{
                    'Result' = $currentMatch
                }
            }
            TestScript = { 
                $Config = Get-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml"
                $Matches = @([regex]::matches($Config, "<arguments>[\s\S]*?<\/arguments>", 'IgnoreCase'))
				$argString = "-Xrs -Xmx"+$Using:JenkinsXmx+"m -XX:MaxPermSize="+$Using:JenkinsMaxPermSize+"m -Djenkins.install.runSetupWizard=false -Dhudson.lifecycle=hudson.lifecycle.WindowsServiceLifecycle -jar `"%BASE%\jenkins.war`" --httpPort="+$Using:JenkinsPort+" --httpListenAddress=127.0.0.1 --webroot=`"%BASE%\war`""
                $currentMatch = $Matches.Groups[1].Value
				
				Write-Verbose "Current service arguments: $currentMatch"
				Write-Verbose "Should be service arguments: $argString"
                
                If ($argString -ne $currentMatch) {
                    # Jenkins port must be changed
                    Return $False
                }
                # Jenkins is already on correct port
                Return $True
            }
            DependsOn = "[cChocoPackageInstaller]installJenkins"
        }
		
		File JenkinsAuthenticationSetup 
		{
			DestinationPath = $JenkinsInitScriptPath
			SourcePath = (Join-Path $InstallConfDirectory "solita_jenkins_security_realm.groovy")
			Ensure = "Present"
			Type = "File"
			Checksum = "modifiedDate"
			Force = $true
			MatchSource = $true
			DependsOn = "[cChocoPackageInstaller]installJenkins"
		}
		Script SetJenkinsAuthenticationUsername
		{
			SetScript = {
				$username = $Using:JenkinsUsername
				(Get-Content $Using:JenkinsInitScriptPath).Replace($Using:JenkinsUsernameTemplate,$username) | Set-Content $Using:JenkinsInitScriptPath
			}
			GetScript = {
				$containsReplacaple = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsUsernameTemplate } | ? { $_ -contains $true }
				$aResult = $containsReplacaple -eq $True
				Return @{
					'Result' = $aResult
				}
			}
			TestScript = {
				$containsReplacaple = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsUsernameTemplate } | ? { $_ -contains $true }
				if($containsReplacaple -eq $True)
				{
					# needs configuration
					Return $False
				}
				Return $True
			}
		}
		Script SetJenkinsAuthenticationPassword
		{
			SetScript = {
				$password = $Using:JenkinsPassword
				(Get-Content $Using:JenkinsInitScriptPath).Replace($Using:JenkinsPasswordTemplate,$password) | Set-Content $Using:JenkinsInitScriptPath 
			}
			GetScript = {
				$containsReplacaple = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsPasswordTemplate } | ? { $_ -contains $true }
				$aResult = $containsReplacaple -eq $True
				Return @{
					'Result' = $aResult
				}
			}
			TestScript = {
				$containsReplacaple = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsPasswordTemplate } | ? { $_ -contains $true }
				if($containsReplacaple -eq $True)
				{
					# needs configuration
					Return $False
				}
				Return $True
			}
		}
		Service JenkinsService
        {
            Name        = "Jenkins"
            StartupType = "Automatic"
            State       = "Running"
			DependsOn = "[cChocoPackageInstaller]installJenkins","[Script]SetJenkinsServiceArguments","[File]JenkinsAuthenticationSetup","[Script]SetJenkinsAuthenticationUsername","[Script]SetJenkinsAuthenticationPassword"
        } 
		
		Script InstallJenkinsPlugins
		{
			SetScript = {
				$plugins = $Using:JenkinsPlugins
				$port = $Using:JenkinsPort
				$password = $Using:JenkinsPassword
				$username = $Using:JenkinsUsername
				
				# Make sure that Jenkins is in the configurated state
				Restart-Service `
                    -Name Jenkins
				Start-Sleep -s 15
				
				# Wait a bit for Jenkins to get online 
				$request = [system.Net.WebRequest]::Create("http://localhost:${port}")
				for ($i = 1; $i -le 10; $i++) {
					try {
						   $result = $request.GetResponse()
					} catch [System.Net.WebException] {
						   $result = $_.Exception.Response
					}
					
					if ($result -is "System.Net.HttpWebResponse" -and $result.StatusCode -ne "") {
						$done = "Got status"
						break
					}
					
					Write-Host "Get status attempt number $($i) failed. Retrying..."
					Start-Sleep -s 5
				}
				
				# Install plugins
				
				foreach ($jplug in $plugins) {
					Write-Verbose "installing $jplug"
					java -jar ${ENV:ProgramFiles(x86)}\Jenkins\war\WEB-INF\jenkins-cli.jar  -s "http://localhost:${port}" install-plugin $jplug --username $username --password $password
					# Wait a bit, Jenkins is kind of slow 
					Start-Sleep -s 5
				}
                Write-Verbose -Verbose "Restarting Jenkins"
                Restart-Service `
                    -Name Jenkins
			}
			GetScript = {
				Return @{ Result = Get-ChildItem "${ENV:ProgramFiles(x86)}\Jenkins\plugins" | Select Name }
			}
			TestScript = {
				# Sanity check to bypass weird folder does not exist problem
				if(!(Test-Path "${ENV:ProgramFiles(x86)}\Jenkins\plugins"))
				{
					Return $False
				}
				# Check if there are plugins
				$directoryInfo = Get-ChildItem "${ENV:ProgramFiles(x86)}\Jenkins\plugins" | Measure-Object
				# Directory is empty, do the update
				if ($directoryInfo.Count -eq 0) {
					Return $False
				}
				# Do not make update 
				Return $True
			}
			DependsOn = "[cChocoPackageInstaller]installJenkins","[Script]SetJenkinsServiceArguments","[File]JenkinsAuthenticationSetup","[Service]JenkinsService","[Script]SetJenkinsAuthenticationUsername","[Script]SetJenkinsAuthenticationPassword"
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
$myusername = Read-Host "Give username for jenkins_user"
$securepwd = Read-Host -AsSecureString "Give password for jenkins_user"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securepwd)
$mypwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
$jenkinsInitScript = "${ENV:ProgramFiles(x86)}\Jenkins\init.groovy.d\solita_jenkins_security_realm.groovy"
$jenkinsUidTemplate = "REPLACE_jenkinsusername_REPLACE"
$jenkinsPwTemplate = "REPLACE_jenkinspassword_REPLACE"
# Set WSMan envelope size bigger, to get git.install through 
Set-WSManInstance -ValueSet @{MaxEnvelopeSizekb = "1000"} -ResourceURI winrm/config
# Start the actual jenkins configuration
$jenkinsPlugins = Get-Content .\misc\jenkins_plugins.txt 
$currentPath = (split-path -parent $MyInvocation.MyCommand.Definition)
$installConfPath = (join-path $currentPath "misc")
JENKINS_CI -JenkinsPort 8080 -JenkinsPlugins $jenkinsPlugins -JenkinsUsername $myusername -JenkinsPassword $mypwd -InstallConfDirectory $installConfPath -JenkinsInitScriptPath $jenkinsInitScript -JenkinsUsernameTemplate $jenkinsUidTemplate -JenkinsPasswordTemplate $jenkinsPwTemplate -ConfigurationData $ConfigData
Start-DscConfiguration -Path .\JENKINS_CI -Wait -Verbose -Force