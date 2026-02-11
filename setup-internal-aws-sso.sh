#!/usr/bin/env bash
set -euo pipefail

# WeareVolt Internal AWS SSO setup script
# Configures AWS SSO profile for WeareVolt internal accounts (spice, pjc, alex, internal).
# SSO portal: https://wearevolt.awsapps.com/start/#/

SSO_START_URL="https://wearevolt.awsapps.com/start/#/"
SSO_REGION="us-east-1"
AWS_REGION="us-east-1"
SSO_SESSION_NAME="wearevolt-internal"

# Account IDs (from management/wearevolt/.../idc/accounts.yaml); override via env if needed
ACCOUNT_ID_SPICE="${ACCOUNT_ID_SPICE:-820345161825}"      # Spice
ACCOUNT_ID_PJC="${ACCOUNT_ID_PJC:-646282686055}"         # WAV-PJC
ACCOUNT_ID_ALEX="${ACCOUNT_ID_ALEX:-631170821846}"       # Alex
ACCOUNT_ID_INTERNAL="${ACCOUNT_ID_INTERNAL:-539247483493}" # WAV-COMMON

# ── Profile selection ─────────────────────────────────────────────────
echo ""
echo "WeareVolt Internal AWS SSO Setup"
echo "==============================="
echo ""
echo "Select profile:"
echo "  1) spice"
echo "  2) pjc"
echo "  3) alex"
echo "  4) internal"
echo ""
read -rp "Enter number [1-4]: " choice

case "$choice" in
    1)
        PROFILE_NAME="spice"
        ACCOUNT_ID="${ACCOUNT_ID_SPICE}"
        ;;
    2)
        PROFILE_NAME="pjc"
        ACCOUNT_ID="${ACCOUNT_ID_PJC}"
        ;;
    3)
        PROFILE_NAME="alex"
        ACCOUNT_ID="${ACCOUNT_ID_ALEX}"
        ;;
    4)
        PROFILE_NAME="internal"
        ACCOUNT_ID="${ACCOUNT_ID_INTERNAL}"
        ;;
    *)
        echo "ERROR: Invalid choice. Expected 1, 2, 3, or 4."
        exit 1
        ;;
esac

if [ -z "${ACCOUNT_ID}" ]; then
    echo ""
    echo "ERROR: Account ID for profile '$PROFILE_NAME' is not set."
    echo "Set it via environment variable (e.g. ACCOUNT_ID_SPICE=123456789012) or edit this script."
    exit 1
fi

echo ""
echo "Profile    : $PROFILE_NAME"
echo "Account ID : $ACCOUNT_ID"
echo ""

# ── Check prerequisites ───────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
    echo "ERROR: 'aws' is not installed. Please install AWS CLI first."
    exit 1
fi

# ── Configure SSO profile ─────────────────────────────────────────────
echo "Configuring AWS SSO profile '$PROFILE_NAME'..."
echo ""

AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
mkdir -p "$(dirname "$AWS_CONFIG_FILE")"

# Remove existing profile block for this profile only (keep sso-session)
if [ -f "$AWS_CONFIG_FILE" ]; then
    python3 -c "
import re

config = open('$AWS_CONFIG_FILE').read()
config = re.sub(r'\[profile $PROFILE_NAME\]\n(?:[^\[]*\n)*', '', config)
config = re.sub(r'\n{3,}', '\n\n', config).strip()
print(config)
" > "${AWS_CONFIG_FILE}.tmp" 2>/dev/null || true
    if [ -s "${AWS_CONFIG_FILE}.tmp" ]; then
        mv "${AWS_CONFIG_FILE}.tmp" "$AWS_CONFIG_FILE"
    else
        rm -f "${AWS_CONFIG_FILE}.tmp"
    fi
fi

# Append new SSO session (only if not already present) and profile
if ! grep -q "\[sso-session $SSO_SESSION_NAME\]" "$AWS_CONFIG_FILE" 2>/dev/null; then
    cat >> "$AWS_CONFIG_FILE" <<EOF

[sso-session $SSO_SESSION_NAME]
sso_start_url = $SSO_START_URL
sso_region = $SSO_REGION
sso_registration_scopes = sso:account:access
EOF
fi

cat >> "$AWS_CONFIG_FILE" <<EOF

[profile $PROFILE_NAME]
sso_session = $SSO_SESSION_NAME
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

# ── EKS (optional): uncomment and set CLUSTER_NAME if this account has EKS
# echo "Configuring kubectl for EKS cluster..."
# aws eks update-kubeconfig --name CLUSTER_NAME --region $AWS_REGION --profile "$PROFILE_NAME"

echo "======================="
echo "DONE: Setup complete."
echo ""
echo "To use this profile in your terminal, run:"
echo ""
echo "  export AWS_PROFILE=$PROFILE_NAME"
echo ""
