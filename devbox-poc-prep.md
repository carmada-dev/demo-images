# What do we need for a Dev Box PoC?

This document is a collection of information and links to resources that are needed to prepare a Microsoft DevBox PoC.

This Microsoft DevBox PoC documentation was created by [Markus Heiliger (DevDiv)](https://github.com/markusheiliger) and [Julia Kordick (Dev GBB)](https://github.com/jkordick)

## Contents

- [Overview](#overview)  
- [Licensing](#licensing)
- [Establish the POC team](#establish-the-poc-team)
- [DevBox Infrastructure Considerations](#devbox-infrastructure-considerations)
  - [Networking](#networking)
    - [Locations](#locations)
    - [Microsoft hosted or self-hosted networks](#microsoft-hosted-or-self-hosted-networks)
    - [Firewall](#firewall)
  - [Security](#security)  
  - [Images/DevBox customizations](#imagesdevbox-customizations)
- [Dev Box POC Implementation](#implementation)
     - [Quota request (optional)](#step-1-submit-a-quota-request-if-needed)
     - [Configure Intune, Entra](#step-2-configure-intune--entra-id-conditional-access)
     - [Configure networking](#step-3-configure-custom-networking-if-needed)
     - [Configure Dev Center, Project, Dev Box, and Pool](#step-4-configure-a-dev-center-a-project-a-dev-box-definition-and-a-pool)
     - [Create Custom Images and Customize existing images](#step-5-create-custom-images--customizations-if-needed)
- [Onboarding the software development team](#onboarding-the-software-development-team)
    - [Add Dev Box Users](#step-1-add-the-software-development-team-as-dev-box-users)
    - [Creating Dev Boxes using self-service](#step-2-ask-the-software-development-team-to-start-creating-dev-boxes-self-service)
    - [Start connecting to, and using, Dev Boxes](#step-3-start-connecting-to-and-using-dev-boxes)
    - [Manage, personalize, customize and troubleshoot Dev Boxes](#step-4-manage-personalize-customize-and-troubleshoot-dev-boxes)
- [Next steps](#next-steps)  

## Overview

Microsoft DevBox is a cloud-based development environment that is built on top of Azure Virtual Desktop (AVD). It is designed to provide a secure, scalable, and compliant development environment for developers who need (not only) to work on sensitive projects.
Find the offical documentation [here](https://learn.microsoft.com/en-us/azure/dev-box/overview-what-is-microsoft-dev-box)
and the current roadmap [here](https://learn.microsoft.com/en-us/azure/dev-box/dev-box-roadmap).

> If all prerequisites are met the estimated time to complete a DevBox PoC is about 2-3 days.

## Licensing

In general these individual licenses are needed:

1. Entra AD P1
2. Windows 10/11
3. Intune
4. additional for EPM (Elevated Priviledge Management) Intune Suite

The licenses do not need to be bought indiviually, they are included in the following bundles:

- M365 E3
- M365 E5

### Establish the POC team

A successful POC rollout requires involvement from both your IT/Platform team and your software development team. The IT/Platform team will identify the infrastructure requirements and enable the POC onboarding process, while the dev team will identify developers’ needs and evaluate the end-user experience. One of the biggest challenges is oftenly to get all the needed information/configurations from the right people. Here is a list of the needed Personas/SMEs:

#### IT/Platform domain expertise
- **Entra ID/AD Admins** (for authentication, conditional access, etc.)
- **Networking-Admins** (only needed, in case of self-hosted networks: in which network are the DevBoxes located and to which networks do they need access? (hub & spoke, peering, etc.))
- **Firewall-Admins** (egress port enabling, netscope and zscaler configuration, etc.)
- **Intune-/Systemcenter-Admins or Client-Management** (to define and apply policies, etc.)
- **Cloud Center of Excellence** (if there is a cloud adoption framework or similar in place/in execution: how to extend the existing landing zone, etc.)

> If you have an existing Azure Landing Zone, we always recommend to use these already existing resources.

- **Platform Engineering-Team** (to manage the DevCenter, projects and (custom-) images, communication link Devs and other stakeholders, etc.)

#### Software development team
Engage early with the software development team that will be onboarded to the POC stage. Select 2-3 teams.  Spend time understanding and capturing their needs and expectations. A key decision is whether developers need access to on-premises resources, which will influence the network design and security requirements.

> Guidance: Try to get a good mix of different project complexities

#### Identify a POC v-team lead
A POC leader on your side will play a crucial role beyond being a point of contact for the POC team. The POC lead should be someone interested in driving and achieving the POC goals and, ideally, have Azure domain expertise.

## Define requirements & success criteria
Setting success criteria for the POC stage is essential. A successful POC should not take longer than three months. Once the POC team defines requirements and signs off on the infrastructure design, you should be able to set up the Dev Box infrastructure and onboard the POC dev teams. The remaining time can be used to evaluate the service and gather feedback.

## DevBox Infrastructure Considerations

### Subscription
#### Privileges needed
For the subscription, the following privileges, access and licenses might be required for one or more people. 
-	admin privileges on the subscription
-	Entra privileges to manage conditional access
-	Entra/AD permissions for domain joining new Dev Boxes
-	Intune admin access

#### Subscription Service Limits
There are default subscription limits for dev centers, network connections, and dev box definitions. For more information, see [Microsoft Dev Box limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#microsoft-dev-box-limits). If need be, a request to increase quota can be submitted: [Manage quota for Microsoft Dev Box resources](https://learn.microsoft.com/en-us/azure/dev-box/how-to-request-quota-increase)


### Networking

Network connections control where dev boxes are created and hosted, and enable you to connect to other Azure or corporate resources. Depending on your level of control, you can use Microsoft-hosted network connections or bring your own Azure network connections.

Below are three general Networking topics to consider:

#### Locations

Determine the region to deploy in. Some considerations to help you are:
-	How many locations are required? 
-	Is there a central location for egress that could affect the latency of Dev Boxes? 
For example, if we have a tech hub in India and an IT headquarters in Germany, does the traffic need to route through Germany, or can it route through India? 
-	Should we consider establishing a dedicated hub-and-spoke model for each region?


#### Microsoft hosted or self-hosted networks

> We recommend to use Microsoft hosted networks with Azure AD only.

You can choose between Microsoft-hosted and self-hosted networks. With Microsoft-hosted networks, network configuration is handled for you, as the Dev Box connects to the Azure AD authentication network. With self-hosted networks, you must configure the network yourself, giving you more control over the setup.

A self-hosted network is required in scenarios involving a hybrid domain join. In this situation, the network must be connected to the Windows domain controller. Windows AD and Azure AD (including computer accounts) need to be synced frequently, with the standard interval being 30 minutes, though a shorter interval is recommended. This ensures that the user can log in immediately after a new DevBox has been created.

> You need a hybrid domain join if you are using Systemcenter instead of Intune for the client management.

#### Firewall

To enable the DevBox to access necessary resources, it is important to configure your firewall to allow specific endpoints/ports and ensure that traffic inspection is not occurring. Review the [network/firewall requirements](https://learn.microsoft.com/en-us/azure/dev-box/concept-dev-box-network-requirements?tabs=W365).

### Security

- **Client management**: Identify which security tools are currently running or need to run on the machines (e.g., ZScaler, Crowdstrike, Netskope). Ensure that the egress endpoints are enabled and that there is no traffic inspection occurring.

- **Developer permissions**: etermine the required permission level for developers on the machines (standard user, EPM (Elevated Privilege Management), local admin).

- **Existing Security baselines**: Assess any existing security baselines that need to be applied. It is recommended to create a test project and apply all existing security baselines to verify their compatibility with virtual developer machines. Note that many of these existing policies originate from hardware requirements and may not be fully applicable to virtual machines. Test, evaluate, and adjust them as necessary.

### Images/DevBox customizations

> We recommend beginning with one of our existing marketplace images and fine-tuning your custom images later. 

If you wish to create your own images, we suggest utilizing the following repository to get started, which includes CI/CD templates for GitHub Actions and Azure Pipelines.

Regarding custom images, it is essential to clarify the following topics:
-	At which level do you intend to customize the devbox image? (project, devcenter, user)
-	To what extent do you want to allow personal preferences/user customization? (uploaded as YAML via the devbox dev portal)


#### Legal

Are there any legal requirements that need to be considered? (e.g., archiving, self-contained images, etc.)

## Implementation 
### Step 1: Submit a quota request if needed
•	[Manage quota for Microsoft Dev Box resources](https://learn.microsoft.com/en-us/azure/dev-box/how-to-request-quota-increase)
### Step 2: Configure Intune & Entra ID conditional access
-	[Configuring Microsoft Intune conditional access policies for dev boxes - Microsoft Dev Box | Microsoft Learn](https://learn.microsoft.com/en-us/azure/dev-box/how-to-configure-intune-conditional-access-policies)
-	[Configure Microsoft Intune Endpoint Privilege Management - Microsoft Dev Box | Microsoft Learn](https://learn.microsoft.com/en-us/azure/dev-box/how-to-elevate-privilege-dev-box)
### Step 3: Configure custom networking if needed
-	[Network connectivity](https://learn.microsoft.com/en-us/azure/dev-box/concept-dev-box-architecture#network-connectivity)
-	[Configure network connections - Microsoft Dev Box | Microsoft Learn](https://learn.microsoft.com/en-us/azure/dev-box/how-to-configure-network-connections?tabs=AzureADJoin)
-	[Microsoft Dev Box Networking Requirements - Microsoft Dev Box | Microsoft Learn](https://learn.microsoft.com/en-us/azure/dev-box/concept-dev-box-network-requirements?tabs=W365)
### Step 4: Configure a Dev Center, a Project, a Dev Box Definition, and a Pool
-	[Quickstart: Configure Microsoft Dev Box - Microsoft Dev Box | Microsoft Learn](https://learn.microsoft.com/en-us/azure/dev-box/quickstart-configure-dev-box-service)
### Step 5: Create custom Images & customizations if needed
Instead of creating a new custom image for your Dev Box deployment or POC team, you can leverage [Dev Box’s customizations and imaging platform](https://aka.ms/devbox/team-customization) to get started quickly and create code-ready configs without imaging expertise. 

Alternative experiences (Not recommended) :
-	[Capture an image of a VM using the portal](https://learn.microsoft.com/en-us/azure/virtual-machines/capture-image-portal)
-	[Customize your dev box with tasks](https://learn.microsoft.com/en-us/azure/dev-box/how-to-customize-dev-box-setup-tasks)

### Onboarding the Software Development Team
#### Step 1: Add the software development team as Dev Box users
-	[Grant user-level access to projects in Microsoft Dev Box](https://learn.microsoft.com/en-us/azure/dev-box/how-to-dev-box-user)
-	[Configure security groups for role-based access control](https://learn.microsoft.com/en-us/azure/dev-box/concept-dev-box-deployment-guide#step-3-configure-security-groups-for-role-based-access-control)

#### Step 2: Ask the software development team to start creating Dev Boxes (self-service)
-	[Manage a dev box in the developer portal](https://learn.microsoft.com/en-us/azure/dev-box/how-to-create-dev-boxes-developer-portal)

#### Step 3: Start connecting to and using Dev Boxes
-	[Connect to Dev Boxes using Windows App](https://learn.microsoft.com/en-us/azure/dev-box/how-to-connect-to-dev-box-with-windows-app)

#### Step 4: Manage, personalize, customize and troubleshoot Dev Boxes
-	[Manage Dev Boxes from Dev Portal](https://learn.microsoft.com/en-us/azure/dev-box/how-to-create-dev-boxes-developer-portal)
-	[Customize Dev Box at Provisioning from Dev Portal](https://learn.microsoft.com/en-us/azure/dev-box/how-to-customize-dev-box-setup-tasks)
-	[Customize Dev Box Post Provisioning from Dev Home](https://learn.microsoft.com/en-us/azure/dev-box/how-to-use-dev-home-customize-dev-box) 
-	[Troubleshoot Dev Box Connectivity Issues](https://learn.microsoft.com/en-us/azure/dev-box/how-to-troubleshoot-repair-dev-box)


## Next Steps
-	Implement Infrastructure as Code (IaC) for the general DevBox configuration (DevCenter, Projects, networking, identities, etc.).
-	Establish GitOps for the DevBox configuration, new projects, and other related processes.


[def]: Implementing-DevBox)