#!/usr/bin/env bash
set -euo pipefail

# Moneyball AWS SSO + EKS setup script
# Configures AWS SSO profile and connects to the EKS cluster for the selected environment.
# Automatically picks the highest-privilege role available to the user.
# Usage: ./setup-moneyball-aws-sso.sh

SSO_START_URL="https://moneyball-ribbit.awsapps.com/start/#/"
SSO_REGION="us-east-1"
AWS_REGION="us-east-1"

# Role priority: highest privilege first
ROLE_PRIORITY=(
    "AdministratorAccess"
    "PowerUserAccess"
    "DataSecretsAccess"
    "DataUserAccess"
    "DevAccess"
    "QAAccess"
)

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
read -rp "Enter number [1-3]: " env_choice

case "$env_choice" in
    1)
        ENV_NAME="qa"
        ACCOUNT_ID="590184074319"
        CLUSTER_NAME="qa"
        ;;
    2)
        ENV_NAME="stg"
        ACCOUNT_ID="412215357866"
        CLUSTER_NAME="stg"
        ;;
    3)
        ENV_NAME="prod"
        ACCOUNT_ID="905418253345"
        CLUSTER_NAME="prod"
        ;;
    *)
        echo "ERROR: Invalid choice. Expected 1, 2, or 3."
        exit 1
        ;;
esac

# ── Check prerequisites ───────────────────────────────────────────────
for cmd in aws kubectl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is not installed. Please install it first."
        exit 1
    fi
done

# ── Write SSO session config (needed for login) ───────────────────────
AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
mkdir -p "$(dirname "$AWS_CONFIG_FILE")"

SESSION_NAME="moneyball-${ENV_NAME}"

# Clean up old session block if exists
if [ -f "$AWS_CONFIG_FILE" ]; then
    python3 -c "
import re

config = open('${AWS_CONFIG_FILE}').read()
config = re.sub(r'\[sso-session ${SESSION_NAME}\]\n(?:[^\[]*\n)*', '', config)
config = re.sub(r'\n{3,}', '\n\n', config).strip()
print(config)
" > "${AWS_CONFIG_FILE}.tmp" 2>/dev/null || true
    if [ -s "${AWS_CONFIG_FILE}.tmp" ]; then
        mv "${AWS_CONFIG_FILE}.tmp" "$AWS_CONFIG_FILE"
    else
        rm -f "${AWS_CONFIG_FILE}.tmp"
    fi
fi

cat >> "$AWS_CONFIG_FILE" <<EOF

[sso-session ${SESSION_NAME}]
sso_start_url = ${SSO_START_URL}
sso_region = ${SSO_REGION}
sso_registration_scopes = sso:account:access
EOF

# ── SSO Login ──────────────────────────────────────────────────────────
echo ""
echo "Logging in via AWS SSO (a browser window will open)..."
aws sso login --sso-session "$SESSION_NAME"

echo ""
echo "OK: SSO login successful."
echo ""

# ── Get SSO access token from cache ───────────────────────────────────
SSO_CACHE_DIR="$HOME/.aws/sso/cache"
ACCESS_TOKEN=""

if [ -d "$SSO_CACHE_DIR" ]; then
    ACCESS_TOKEN=$(python3 -c "
import json, glob, os, sys
from datetime import datetime, timezone

cache_dir = '${SSO_CACHE_DIR}'
best_token = None
best_time = None

for f in glob.glob(os.path.join(cache_dir, '*.json')):
    try:
        data = json.load(open(f))
        if 'accessToken' not in data:
            continue
        if 'startUrl' in data and data['startUrl'] != '${SSO_START_URL}':
            continue
        expires = data.get('expiresAt', '')
        if expires:
            exp_time = datetime.fromisoformat(expires.replace('Z', '+00:00'))
            if exp_time < datetime.now(timezone.utc):
                continue
            if best_time is None or exp_time > best_time:
                best_time = exp_time
                best_token = data['accessToken']
    except Exception:
        continue

if best_token:
    print(best_token)
else:
    sys.exit(1)
" 2>/dev/null) || true
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "ERROR: Could not retrieve SSO access token. Please try again."
    exit 1
fi

# ── Discover available roles ──────────────────────────────────────────
echo "Discovering available roles for account $ACCOUNT_ID..."

AVAILABLE_ROLES=$(aws sso list-account-roles \
    --account-id "$ACCOUNT_ID" \
    --access-token "$ACCESS_TOKEN" \
    --region "$SSO_REGION" \
    --query 'roleList[].roleName' \
    --output text 2>/dev/null) || true

if [ -z "$AVAILABLE_ROLES" ]; then
    echo "ERROR: No roles available for account $ACCOUNT_ID."
    echo "       You may not have access to the $ENV_NAME environment."
    echo "       Contact DevOps to request access."
    exit 1
fi

echo "Available roles: $AVAILABLE_ROLES"

# ── Pick the best role by priority ────────────────────────────────────
SSO_ROLE=""
for role in "${ROLE_PRIORITY[@]}"; do
    if echo "$AVAILABLE_ROLES" | grep -qw "$role"; then
        SSO_ROLE="$role"
        break
    fi
done

if [ -z "$SSO_ROLE" ]; then
    # Fallback: use the first available role
    SSO_ROLE=$(echo "$AVAILABLE_ROLES" | awk '{print $1}')
fi

echo "Selected role  : $SSO_ROLE"
echo ""

# ── Build profile name ────────────────────────────────────────────────
PROFILE_NAME="${ENV_NAME}-mb"

# ── Write final profile to AWS config ─────────────────────────────────
echo "Configuring AWS CLI profile '$PROFILE_NAME'..."

# Remove old profile block if exists
if [ -f "$AWS_CONFIG_FILE" ]; then
    python3 -c "
import re

config = open('${AWS_CONFIG_FILE}').read()
config = re.sub(r'\[profile ${PROFILE_NAME}\]\n(?:[^\[]*\n)*', '', config)
config = re.sub(r'\n{3,}', '\n\n', config).strip()
print(config)
" > "${AWS_CONFIG_FILE}.tmp" 2>/dev/null || true
    if [ -s "${AWS_CONFIG_FILE}.tmp" ]; then
        mv "${AWS_CONFIG_FILE}.tmp" "$AWS_CONFIG_FILE"
    else
        rm -f "${AWS_CONFIG_FILE}.tmp"
    fi
fi

cat >> "$AWS_CONFIG_FILE" <<EOF

[profile ${PROFILE_NAME}]
sso_session = ${SESSION_NAME}
sso_account_id = ${ACCOUNT_ID}
sso_role_name = ${SSO_ROLE}
region = ${AWS_REGION}
output = json
EOF

echo "OK: Profile '$PROFILE_NAME' written to $AWS_CONFIG_FILE"
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

# ── Summary ────────────────────────────────────────────────────────────
echo "======================="
echo "DONE: Setup complete."
echo ""
echo "  Environment : $ENV_NAME"
echo "  Role        : $SSO_ROLE"
echo "  Profile     : $PROFILE_NAME"
echo "  EKS cluster : $CLUSTER_NAME"
echo ""
echo "To use this profile in your terminal, run:"
echo ""
echo "  export AWS_PROFILE=$PROFILE_NAME"
echo ""
echo "To switch kubectl context later:"
echo ""
echo "  kubectx $CLUSTER_NAME"
echo ""
