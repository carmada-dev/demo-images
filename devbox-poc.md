# Implementation Guidance for the Dev Box PoC

## Contents

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

> There are considerations and prework to complete before starting implementation, you can find these [here](devbox-poc-prep.md)

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