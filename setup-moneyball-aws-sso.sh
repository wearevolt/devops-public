#!/usr/bin/env bash
set -euo pipefail

# Moneyball AWS SSO + EKS setup script
# Configures AWS SSO profile and connects to the EKS cluster for the selected environment.

SSO_START_URL="https://moneyball-ribbit.awsapps.com/start/#/"
SSO_REGION="us-east-1"
AWS_REGION="us-east-1"

# ── Environment selection ──────────────────────────────────────────────
echo ""
echo "Moneyball AWS SSO Setup"
echo "======================="
echo ""
echo "Select environment:"
echo "  1) QA"
echo "  2) Staging"
echo "  3) Production"
echo ""
read -rp "Enter number [1-3]: " choice

case "$choice" in
    1)
        ENV_NAME="qa"
        ACCOUNT_ID="590184074319"
        PROFILE_NAME="qa-mb"
        CLUSTER_NAME="qa"
        ;;
    2)
        ENV_NAME="stg"
        ACCOUNT_ID="412215357866"
        PROFILE_NAME="stg-mb"
        CLUSTER_NAME="stg"
        ;;
    3)
        ENV_NAME="prod"
        ACCOUNT_ID="905418253345"
        PROFILE_NAME="prod-mb"
        CLUSTER_NAME="prod"
        ;;
    *)
        echo "ERROR: Invalid choice. Expected 1, 2, or 3."
        exit 1
        ;;
esac

echo ""
echo "Environment : $ENV_NAME"
echo "Account ID  : $ACCOUNT_ID"
echo "Profile     : $PROFILE_NAME"
echo "EKS cluster : $CLUSTER_NAME"
echo ""

# ── Check prerequisites ───────────────────────────────────────────────
for cmd in aws kubectl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is not installed. Please install it first."
        exit 1
    fi
done

# ── Configure SSO profile ─────────────────────────────────────────────
echo "Configuring AWS SSO profile '$PROFILE_NAME'..."
echo ""

# Write the SSO session and profile directly into AWS config
AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
mkdir -p "$(dirname "$AWS_CONFIG_FILE")"

# Remove existing profile and session blocks if present
if [ -f "$AWS_CONFIG_FILE" ]; then
    # Create a temp file without the old blocks
    python3 -c "
import re, sys

config = open('$AWS_CONFIG_FILE').read()

# Remove existing sso-session block
config = re.sub(r'\[sso-session $ENV_NAME\]\n(?:[^\[]*\n)*', '', config)

# Remove existing profile block
config = re.sub(r'\[profile $PROFILE_NAME\]\n(?:[^\[]*\n)*', '', config)

# Clean up extra blank lines
config = re.sub(r'\n{3,}', '\n\n', config).strip()

print(config)
" > "${AWS_CONFIG_FILE}.tmp" 2>/dev/null || true
    if [ -s "${AWS_CONFIG_FILE}.tmp" ]; then
        mv "${AWS_CONFIG_FILE}.tmp" "$AWS_CONFIG_FILE"
    else
        rm -f "${AWS_CONFIG_FILE}.tmp"
    fi
fi

# Append new SSO session and profile
cat >> "$AWS_CONFIG_FILE" <<EOF

[sso-session $ENV_NAME]
sso_start_url = $SSO_START_URL
sso_region = $SSO_REGION
sso_registration_scopes = sso:account:access

[profile $PROFILE_NAME]
sso_session = $ENV_NAME
sso_account_id = $ACCOUNT_ID
sso_role_name = AdministratorAccess
region = $AWS_REGION
output = json
EOF

echo "OK: Profile '$PROFILE_NAME' written to $AWS_CONFIG_FILE"
echo ""

# ── SSO Login ──────────────────────────────────────────────────────────
echo "Logging in via AWS SSO (a browser window will open)..."
aws sso login --profile "$PROFILE_NAME"

echo ""
echo "OK: SSO login successful."
echo ""

# ── Verify identity ───────────────────────────────────────────────────
echo "Verifying AWS identity..."
aws sts get-caller-identity --profile "$PROFILE_NAME"
echo ""

# ── Configure EKS kubeconfig ──────────────────────────────────────────
echo "Configuring kubectl for EKS cluster '$CLUSTER_NAME' in $AWS_REGION..."
aws eks update-kubeconfig \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --profile "$PROFILE_NAME"

echo ""
echo "OK: kubeconfig updated."
echo ""

# ── Set AWS_PROFILE for current session hint ──────────────────────────
echo "======================="
echo "DONE: Setup complete."
echo ""
echo "To use this profile in your terminal, run:"
echo ""
echo "  export AWS_PROFILE=$PROFILE_NAME"
echo ""
echo "To switch kubectl context later:"
echo ""
echo "  kubectx $CLUSTER_NAME"
echo ""
