# powershell-dsc-jenkins
Repository to host powershell dsc script to setup a jenkins server. 

# Usage 
There are three separated steps how to use 

1. Install Modules for DSC
2. Install build server
3. Protect build server with IIS reverse proxy 

### Install Modules 
Use install-modules in the machine where you start DSC configuration (currently locally in the target machine)

## Install Jenkins 
Before you run jenkins_dsc make sure that you alter default password from groovy file and dsc file. 
Use jenkins_dsc to do the installation magic:
- Installl .NET
- Install Choco
- Install Java
- Install node
- Install python 
- Install visual studio
- Install visual studio web extension
- Install visual studio data extension
- Install notepad++
- Add Java to path
- Install Jenkins
- Setup Jenkins startup arguments for more ram, 80 port and to skip setup wizard
- Create initialization script with groovy for creating solita_jenkins user
- Set Jenkins service to Automatic state and make sure that it is running
- Install jenkins plugins

### IIS reverse proxy setup
Before running iis_reverse_proxy_dsc download corresponding pfx to the running folder and alter the thumbprint to match it
Use iis_reverse_proxy_dsc to install HTTPS certificate
- Install .NET
- Install choco
- Install .NET 4.5
- Install IIS and few features to it
- Install ARR and Url Rewrite
- Remove default website
- Create website for proxying connections
- Make HTTP to HTTPS redirect rule
- Set up ARR proxy setting for TLS offloading
- Create url rewrite rules for proxytunnel 