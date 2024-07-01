# Configuration options:
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "--github-org      The GitHub organization name"
    echo "--github-repo     The GitHub repository name"
    echo "--vm-name         The name of the VM"
    echo "--vm-size         The size of the VM (SKU)"
    echo "--subnet-id       The Subnet ID for the VM"
    echo "--runner-version  The GitHub Runner version"
    echo "--resource-group  The Azure Resource Group name"
    echo "--location        The Azure region"
    echo "-h, --help        Display this help and exit"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --github-org) GITHUB_ORGANIZATION_NAME="$2"; shift ;;
        --github-repo) GITHUB_REPOSITORY_NAME="$2"; shift ;;
        --vm-name) AGENT_VM_NAME="$2"; shift ;;
        --vm-size) AGENT_VM_SIZE="$2"; shift ;;
        --subnet-id) AGENT_VM_SUBNET_ID="$2"; shift ;;
        --runner-version) GITHUB_RUNNER_VERSION="$2"; shift ;;
        --resource-group) RESOURCE_GROUP_NAME="$2"; shift ;;
        --location) LOCATION="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

echo "GitHub Organization: $GITHUB_ORGANIZATION_NAME"
echo "GitHub Repository: $GITHUB_REPOSITORY_NAME"
echo "VM Name: $AGENT_VM_NAME"
echo "VM Size: $AGENT_VM_SIZE"
echo "Subnet ID: $AGENT_VM_SUBNET_ID"
echo "GitHub Runner Version: $GITHUB_RUNNER_VERSION"
echo "Resource Group Name: $RESOURCE_GROUP_NAME"
echo "Location: $LOCATION"

# Generate a runner registration token:
GITHUB_RUNNER_TOKEN=$(gh api repos/$GITHUB_ORGANIZATION_NAME/$GITHUB_REPOSITORY_NAME/actions/runners/registration-token --method "POST" --header "Accept: application/vnd.github+json" --jq .token)

# Create and register a runner VM:
cat <<EOF | az vm create \
  --name $AGENT_VM_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --location $LOCATION \
  --generate-ssh-keys \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" \
  --nsg "" \
  --public-ip-address "" \
  --size $AGENT_VM_SIZE \
  --subnet $AGENT_VM_SUBNET_ID \
  --custom-data @-
#cloud-config:
package_update: true
package_upgrade: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg-agent
  - libicu60
  - libkrb5-3
  - liblttng-ust0
  - liblttng-ust-ctl4
  - libssl1.1
  - liburcu6
  - lsb-release
  - software-properties-common
  - zlib1g

runcmd:
  # Install Docker
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  - sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  - sudo apt-get update
  - sudo apt-get install -y docker-ce docker-ce-cli containerd.io

  # Install Azure CLI
  - curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

  # Setup GitHub Actions Runner
  - mkdir /actions-runner
  - cd /actions-runner
  - curl -s -O -L https://github.com/actions/runner/releases/download/v${GITHUB_RUNNER_VERSION}/actions-runner-linux-x64-${GITHUB_RUNNER_VERSION}.tar.gz
  - tar xzf ./actions-runner-linux-x64-${GITHUB_RUNNER_VERSION}.tar.gz
  - RUNNER_ALLOW_RUNASROOT=1 ./config.sh --url https://github.com/${GITHUB_ORGANIZATION_NAME}/${GITHUB_REPOSITORY_NAME} --token ${GITHUB_RUNNER_TOKEN} --unattended
  - RUNNER_ALLOW_RUNASROOT=1 ./svc.sh install
  - RUNNER_ALLOW_RUNASROOT=1 ./svc.sh start
EOF
