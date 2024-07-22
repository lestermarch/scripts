# Configuration options:
usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "-gho, --github-org <orgName>                  The GitHub organization name"
  echo "-ghr, --github-repo <repoName>                The GitHub repository name"
  echo "-ghe, --github-env [<envName:subscriptionId>] The GitHub environment name and Azure subscription ID, colon delimited"
  echo "-g, --resource-group <rgName>                 The Azure resource group name to create"
  echo "-i, --identity <uidName>                      The Azure user-assigned managed identity to create"
  echo "-l, --location <location>                     The Azure region in which to create resources"
  echo "-s, --storage-account-prefix <prefix>         The prefix for the Azure storage account name"
  echo "-h, --help                                    Show this help message"
  echo ""
  echo "Examples:"
  echo "1. Create a new Azure resource group, deployment identity, and state storage account for a GitHub repository with two environments:"
  echo "  Initialize-AzureDeploymentGitHubRepo.sh \\"
  echo "    --github-org ExampleOrg \\"
  echo "    --github-repo ExampleRepo \\"
  echo "    --github-env 'dev:00000000-0000-0000-0000-000000000001 prod:00000000-0000-0000-0000-000000000002' \\"
  echo "    --resource-group rg-example \\"
  echo "    --identity uid-example \\"
  echo "    --location uksouth \\"
  echo "    --storage-account-prefix stexample"
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -gho | --github-org) GITHUB_ORG=$2; shift ;;
    -ghr | --github-repo) GITHUB_REPO=$2; shift ;;
    -ghe | --github-env) GITHUB_ENVIRONMENTS=$2; shift ;;
    -g | --resource-group) RESOURCE_GROUP=$2; shift ;;
    -i | --identity) IDENTITY=$2; shift ;;
    -l | --location) LOCATION=$2; shift ;;
    -s | --storage-account-prefix) STORAGE_ACCOUNT_PREFIX=$2; shift ;;
    -h | --help) usage; exit 0 ;;
  esac
  shift
done

# Exit on any non-zero status
set -e

# Colourise output
CYAN='\033[0;36m'
WARNING='\033[0;93m'
NC='\033[0m'

# Check if Azure CLI and GitHub CLI are installed
check_command() {
  if ! command -v $1 &> /dev/null; then
    echo -e "${WARNING}$1 is required but not installed${NC}"
    exit 1
  fi
}

check_command az
check_command gh

# Split the GitHub environment into name and subscription ID for each space-delimited pair
IFS=' ' read -r -a GITHUB_ENVS <<< "$GITHUB_ENVIRONMENTS"

# Create the resource group
echo -e "\n${CYAN}=> Creating resource group $RESOURCE_GROUP${NC}"
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

RESOURCE_GROUP_ID=$(az group show \
  --name $RESOURCE_GROUP \
  --query id \
  --output tsv)

# Create the deployment identity
echo -e "\n${CYAN}=> Creating deployment identity $IDENTITY${NC}"
az identity create \
  --name $IDENTITY \
  --resource-group $RESOURCE_GROUP

IDENTITY_CLIENT_ID=$(az identity show \
  --name $IDENTITY \
  --resource-group $RESOURCE_GROUP \
  --query clientId \
  --output tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name $IDENTITY \
  --resource-group $RESOURCE_GROUP \
  --query principalId \
  --output tsv)

IDENTITY_TENANT_ID=$(az identity show \
  --name $IDENTITY \
  --resource-group $RESOURCE_GROUP \
  --query tenantId \
  --output tsv)

# Create the state storage account
ENTROPY=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_PREFIX}${ENTROPY}"
STORAGE_CONTAINER_NAME="${GITHUB_REPO,,}"

echo -e "\n${CYAN}=> Creating state storage account $STORAGE_ACCOUNT_NAME${NC}"
az storage account create \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_RAGZRS \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2

az storage container create \
  --name $STORAGE_CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT_NAME \
  --auth-mode login

STORAGE_ACCOUNT_ID=$(az storage account show \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id \
  --output tsv)

# Create deployment identity role assignments and federations
az role assignment create \
  --assignee-object-id $IDENTITY_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope $STORAGE_ACCOUNT_ID

for GITHUB_ENV in "${GITHUB_ENVS[@]}"; do
  IFS=':' read -r GITHUB_ENV_NAME GITHUB_ENV_SUBSCRIPTION_ID <<< "$GITHUB_ENV"

  echo -e "\n${CYAN}=> Creating $GITHUB_ENV_NAME role assignments to subscription ID $GITHUB_ENV_SUBSCRIPTION_ID${NC}"
  az role assignment create \
    --assignee-object-id $IDENTITY_PRINCIPAL_ID \
    --assignee-principal-type ServicePrincipal \
    --role "Contributor" \
    --scope "/subscriptions/$GITHUB_ENV_SUBSCRIPTION_ID"
  
  az role assignment create \
    --assignee-object-id $IDENTITY_PRINCIPAL_ID \
    --assignee-principal-type ServicePrincipal \
    --role "User Access Administrator" \
    --scope "/subscriptions/$GITHUB_ENV_SUBSCRIPTION_ID"

  echo -e "\n${CYAN}=> Creating $GITHUB_ENV_NAME federation${NC}"
  az identity federated-credential create \
    --name "${GITHUB_ORG}-${GITHUB_REPO}-${GITHUB_ENV_NAME}" \
    --identity-name $IDENTITY \
    --resource-group $RESOURCE_GROUP \
    --audiences "api://AzureADTokenExchange" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "repo:$GITHUB_ORG/$GITHUB_REPO:environment:$GITHUB_ENV_NAME"
done

# Create GitHub variables
echo -e "\n${CYAN}=> Creating GitHub environment variables in $GITHUB_REPO${NC}"
gh variable set TERRAFORM_STATE_SUBSCRIPTION_ID \
  --body $(echo $STORAGE_ACCOUNT_ID | cut -d'/' -f3)

gh variable set TERRAFORM_STATE_RESOURCE_GROUP_NAME \
  --body $RESOURCE_GROUP

gh variable set TERRAFORM_STATE_STORAGE_ACCOUNT_NAME \
  --body $STORAGE_ACCOUNT_NAME

gh variable set TERRAFORM_STATE_CONTAINER_NAME \
  --body $STORAGE_CONTAINER_NAME

for GITHUB_ENV in "${GITHUB_ENVS[@]}"; do
  IFS=':' read -r GITHUB_ENV_NAME GITHUB_ENV_SUBSCRIPTION_ID <<< "$GITHUB_ENV"

  echo -e "\n${CYAN}=> Creating GitHub environment variables in $GITHUB_REPO/$GITHUB_ENV_NAME${NC}"
  gh variable set ARM_CLIENT_ID \
    --env $GITHUB_ENV_NAME \
    --body $IDENTITY_CLIENT_ID

  gh variable set ARM_SUBSCRIPTION_ID \
    --env $GITHUB_ENV_NAME \
    --body $GITHUB_ENV_SUBSCRIPTION_ID

  gh variable set ARM_TENANT_ID \
    --env $GITHUB_ENV_NAME \
    --body $IDENTITY_TENANT_ID
done
