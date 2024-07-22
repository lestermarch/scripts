# Initialize-AzureDeploymentGitHubRepo

This script provisions an Azure resource group, user-assigned managed identity, and storage account used by Terrafrom/Terragrunt for deployments to Azure. The managed identity is federated to a GitHub repository, and repository/environment variables are added.

## Requirements

The following software is required:

- Azure CLI
- GitHub CLI

## Usage

```bash
Options:
  -gho, --github-org            The GitHub organization name
  -ghr, --github-repo           The GitHub repository name
  -ghe, --github-env            The GitHub environment name and Azure subscription ID, colon delimited
  -g, --resource-group          The Azure resource group name to create
  -i, --identity                The Azure user-assigned managed identity to create
  -l, --location                The Azure region in which to create resources
  -s, --storage-account-prefix  The prefix for the Azure storage account name
```

### Example

The following demonstrates example usage and values:

> [!Note]
> Consider the following before deployment:
> 
> - The script should be run from a locally cloned GitHub repository in order to create the necessary GitHub repo/environment variables.
> - The Azure resources will be created in your currently scoped Azure subscription. Confirm or change your subscription context with `az account show` and `az account set -s <subscriptionId>`.

```bash
./Initialize-AzureDeploymentGitHubRepo.sh \
  --github-org "lestermarch" \
  --github-repo "example-repo" \
  --github-env "dev:00000000-0000-0000-0000-000000000001 test:00000000-0000-0000-0000-000000000002" \
  --resource-group "rg-deployment" \
  --identity "uid-deployment" \
  --location "uksouth" \
  --storage-account-prefix "stdeployment"
```
