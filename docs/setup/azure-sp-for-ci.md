---
layout: default
title: Azure Service Principal for CI/CD (OIDC)
---

# 🔑 Azure Service Principal for CI/CD (OIDC federation, no client secrets)

The `deploy.yaml` GitHub Actions workflow needs an Azure identity to talk to AKS. We use **OpenID Connect federation** — GitHub's short-lived OIDC token is traded for an Azure access token at runtime. No long-lived client secrets are ever stored.

Takes ~10 minutes. You run these commands once from a terminal that's already `az login`'d.

## Step 1 — create the app registration

```bash
# Give the SP a recognizable name
az ad app create --display-name "money-honey-ci"

APP_ID=$(az ad app list --display-name "money-honey-ci" --query "[0].appId" -o tsv)
echo "APP_ID=$APP_ID"
```

## Step 2 — create the service principal

```bash
az ad sp create --id "$APP_ID"

SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
echo "SP_OBJECT_ID=$SP_OBJECT_ID"
```

## Step 3 — grant the SP the right roles

Two role assignments are needed:

1. **Contributor on the resource group** — so `deploy.yaml` can read the AKS cluster resource and inspect its secrets for kubeconfig.
2. **Azure Kubernetes Service Cluster User Role** on the AKS cluster — so `azure/aks-set-context` can pull the user-mode kubeconfig (NOT admin — the SP gets RBAC-level access only).

```bash
RG_ID=$(az group show --name money-honey-rg --query id -o tsv)
AKS_ID=$(az aks show -g money-honey-rg -n money-honey-aks --query id -o tsv)

# 1. Contributor on the RG (resource-level reads)
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "$RG_ID"

# 2. AKS Cluster User on the AKS resource (kubeconfig pull)
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "$AKS_ID"
```

## Step 4 — add a federated identity credential

This is the OIDC trust: GitHub's `token.actions.githubusercontent.com` issuer, trusted to exchange tokens for the repo's `main` branch only.

```bash
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "money-honey-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:itsAmeMario0o/money-honey:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

If you later want to allow deploys from a different branch or from pull requests, add additional federated-credentials with distinct `subject` values.

## Step 5 — grab the three values to paste into GitHub

```bash
echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)"
```

## Step 6 — set the GitHub repo secrets

Open **https://github.com/itsAmeMario0o/money-honey/settings/secrets/actions** and add three Actions secrets:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | from step 5 (this is `$APP_ID`) |
| `AZURE_TENANT_ID` | from step 5 |
| `AZURE_SUBSCRIPTION_ID` | from step 5 |

Optional Webex notification secrets (workflows gracefully skip if absent):

| Secret | Value |
|---|---|
| `WEBEX_BOT_TOKEN` | From the Webex bot you created at https://developer.webex.com |
| `WEBEX_ROOM_ID` | The room the bot should post to |

## Step 7 — verify

Trigger a run of the `Quality` workflow by pushing any change to `main` (or manually re-run the latest Quality run from the Actions UI). `quality.yaml` doesn't use these secrets, but confirming that the Actions UI loads the secrets pane (and `deploy.yaml` stops failing with auth errors on its next trigger) is the verification step.

A first end-to-end proof: merge a PR that touches `app/` or `frontend/` — `docker-build.yaml` builds images to GHCR (no Azure SP needed — uses built-in `GITHUB_TOKEN`), and `deploy.yaml` triggers with the Azure SP, pulls the kubeconfig, and runs `kubectl apply`.

## Security notes

- The SP **does not** have admin kubeconfig access. It reads the user kubeconfig which goes through Azure RBAC. If Azure RBAC for Kubernetes is enabled on the cluster, you'd also need to grant the SP's object ID specific Kubernetes RBAC roles (e.g. via an `AzureAD` `ClusterRoleBinding`). For the current v1 setup (`local_account_disabled=false`), the user kubeconfig works directly.
- The federated credential is scoped to `refs/heads/main` — PRs cannot run `deploy.yaml` with this SP.
- No client secret exists. GitHub's OIDC token is the credential; it's short-lived and scoped to a single workflow run.
- Rotate the federated credential name or delete/recreate the SP if the repo is compromised.
