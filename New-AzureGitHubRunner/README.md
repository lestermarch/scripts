# New-AzureGitHubRunner

This script provisions an Azure VM and registers it as a self-hosted GitHub runner for the specified organization/repo.

> [!Note]
> Azure CLI and GitHub CLI are required in order to run this script.

## Software

The following software is installed during provisioning:

- Azure CLI
- Docker
- GitHub Runner Agent

> [!Tip]
> The script can be modified to install different software during provisioning by amending the `runcmd` configuration to suit your requirements.

## Usage

The following options are available:

```bash
Options:
  --github-org      The GitHub organization name
  --github-repo     The GitHub repository name
  --vm-name         The name of the VM
  --vm-size         The size of the VM (SKU)
  --subnet-id       The Subnet ID for the VM
  --runner-version  The GitHub Runner version
  --resource-group  The Azure Resource Group name
  --location        The Azure region
```

### Example

The following demonstrates example usage and values:

```bash
./New-AzureGitHubRunner.sh \
  --github-org "lestermarch" \
  --github-repo "example-repo" \
  --vm-name "vm-example-runner-01" \
  --vm-size "Standard_B2ls_v2" \
  --subnet-id "/subscriptions/.../virtualNetworks/vnet-example/subnets/ExampleSubnet" \
  --runner-version "2.317.0" \
  --resource-group "rg-example" \
  --location "uksouth"
```

> [!Note]
> Make sure you are logged into the appropriate Azure subscription using the Azure CLI before deployment:
>
> ```bash
> az login
> az account set -s {{subscriptionId}}
> ```
