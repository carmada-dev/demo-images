# What do we need for a DevBox PoC?

This document is a collection of information and links to resources that are needed to prepare a Microsoft DevBox PoC.

This Microsoft DevBox PoC documentation was created by [Markus Heiliger (DevDiv)](https://github.com/markusheiliger) and [Julia Kordick (Dev GBB)](https://github.com/jkordick)

## Contents

- [Overview](#overview)  
- [Licensing](#-licensing)
- [Needed Personas/SMEs](#-needed-personassmes)
- [Tech](#-tech)
  - [Networking](#networking)
    - [Locations](#locations)
    - [MS hosted or self-hosted networks](#ms-hosted-or-self-hosted-networks)
    - [Firewall](#-firewall)
  - [Security](#-security)  
  - [Images/DevBox customizations](#imagesdevbox-customizations)
- [Next steps](#next-steps)  

## Overview

Microsoft DevBox is a cloud-based development environment that is built on top of Azure Virtual Desktop (AVD). It is designed to provide a secure, scalable, and compliant development environment for developers who need (not only) to work on sensitive projects.
Find the offical documentation [here](https://learn.microsoft.com/en-us/azure/dev-box/overview-what-is-microsoft-dev-box)
and the current roadmap [here](https://learn.microsoft.com/en-us/azure/dev-box/dev-box-roadmap).

> If all prerequisites are met the estimated time to complete a DevBox PoC is about 2-3 days.

## 💰 Licensing

In general these individual licenses are needed:

1. Entra AD P1
2. Windows 10/11
3. Intune
4. additional for EPM (Elevated Priviledge Management) Intune Suite

The licenses do not need to be bought indiviually, they are included in the following bundles:

- M365 E3
- M365 E5

### 🧑‍💻 Needed Personas/SMEs

One of the biggest challenges is to get all the needed information/configurations from the right people. Here is a list of the needed Personas/SMEs:

- **Entra ID/AD Admins** (for authentication, conditional access, etc.)
- **Networking-Admins** (only needed, in case of self-hosted networks: in which network are the DevBoxes located and to which networks do they need access? (hub & spoke, peering, etc.))
- **Firewall-Admins** (egress port enabling, netscope and zscaler configuration, etc.)
- **Intune-/Systemcenter-Admins or Client-Management** (to define and apply policies, etc.)
- **Cloud Center of Excellence** (if there is a cloud adoption framework or similar in place/in execution: how to extend the existing landing zone, etc.)

> If you have an existing Azure Landing Zone, we always recommend to use these already existing resources.

- **Platform Engineering-Team** (to manage the DevCenter, projects and (custom-) images, communication link Devs and other stakeholders, etc.)
- **2-3 Pilot teams** (*guidance*: try to get a good mix of different project complexities)

## 👾 Tech

### Networking

Let's talk about the most amazing thing in the world: Networking. Here we have three general topics to consider:

#### Locations

How many locations do we need? Do we have a central location for egress that could impact the latency of our DevBoxes? (ex. tech hub in India, company and IT HQ in Germany - does the traffic need to go through Germany or can it go through India?) Do we maybe need to create a dedicated hub & spoke for each region?

#### MS hosted or self-hosted networks

> We recommend to use Microsoft hosted networks with Azure AD only.

You can choose between Microsoft hosted networks and self-hosted networks. If you use Microsoft hosted networks, you don't need to worry about the network configuration. The DevBox will be connected to the network that is used for the Azure AD authentication. If you use self-hosted networks, you need to configure the network that the DevBox will be connected to but you also have more control over the network configuration.

The scenario where you always need a self-hosted network is when you have a **hybrid domain join**. In this case, the network must be connected to the Windows domain controller. Windows AD and Azure AD (+ computer accounts) need to be synced frequently (standard is 30 minutes, we recommend less), so that the user can log in directly after a new DevBox has been created.

> You need a hybrid domain join if you are using Systemcenter instead of Intune for the client management.

#### 🔥 Firewall

To ensure that the DevBox can access the resources that it needs, you need to allow a number of endpoints/ports in your firewall configration(s) and ensure that there is no traffic inspection happening. [Here](https://learn.microsoft.com/en-us/azure/dev-box/concept-dev-box-network-requirements?tabs=W365) you can find all network/firewall requirements.

### 🔒 Security

- **Client management**: Which security tools are running/need to run on the machines? (eg. ZScaler, crowdstrike, netscope) Ensure that the egress endpoints are enabled and that no traffic inspection is happening.

- **Developer permissions**: What permission level do the developers need/want to have on the machines? (standard user, EPM (Elevated Privilege Management), local admin)

- **Existing Security baselines**: Are there any existing security baselines that need to be applied? We recommend creating a test project and apply all the existing security baselines to see if they work also with virtual developer machines. Be mindful that a lot of these existing policies are coming from hardware requirements and might not be applicable in the same way to virtual machines. Test it, evaluate them and adjust them if needed.

### Images/DevBox customizations

> We always recommend to start with one of our exsiting marketplace images and finetune your custom images later on.

If you then want to create your own images we recommend you the following [repository](https://github.com/carmada-dev/demo-images) to get started (with CI/CD templates for GitHub Actions and Azure Pipelines).

About the custom images you need to create clarity about the following topics:

- on which level do you want to customize the devbox image? (project, devcenter, user)
- which level of personal preference/user customization do you want to allow? (uploaded as yaml via the devbox dev portal)

#### Legal

Are there any legal requirements that need to be considered? (eg. archiving, self-contained images, ...)

## Next steps

1. Start the doing :)
2. IaC the general DevBox configuration (DevCenter, Projects, networking, identities etc.)
3. GitOps for the DevBox configuration, new Projects, etc.
