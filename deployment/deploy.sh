#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default environment
ENV=${1:-dev}

echo -e "${GREEN}🚀 Deploying to ${ENV} environment${NC}"

# Check if we're in the right directory
if [ ! -f "deploy/overlays/${ENV}/kustomization.yaml" ]; then
    echo -e "${RED}❌ Error: deploy/overlays/${ENV}/kustomization.yaml not found${NC}"
    echo "Please run this script from the repository root"
    exit 1
fi

# Load environment variables and regenerate kustomization files
if [ -f "deploy/.env" ]; then
    source deploy/.env
    echo -e "${GREEN}📝 Regenerating kustomization files with current settings...${NC}"
    ./deploy/generate-kustomization.sh
else
    echo -e "${YELLOW}⚠️  Warning: deploy/.env not found, using existing kustomization files${NC}"
fi

# Check if .env.secret exists
if [ ! -f "deploy/overlays/${ENV}/.env.secret" ]; then
    echo -e "${YELLOW}⚠️  Warning: deploy/overlays/${ENV}/.env.secret not found${NC}"
    echo "Creating from template..."
    cp "deploy/overlays/${ENV}/.env.secret.example" "deploy/overlays/${ENV}/.env.secret"
    echo -e "${YELLOW}Please edit deploy/overlays/${ENV}/.env.secret with actual values${NC}"
    exit 1
fi

# Pull latest changes
echo -e "${GREEN}📥 Pulling latest changes from Git...${NC}"
git pull

# Apply the configuration
echo -e "${GREEN}📦 Applying Kubernetes manifests...${NC}"
kubectl apply -k "deploy/overlays/${ENV}"

# Wait for deployments
echo -e "${GREEN}⏳ Waiting for deployments to be ready...${NC}"
kubectl -n todo-app rollout status deployment/postgres --timeout=120s
kubectl -n todo-app rollout status deployment/todo-api --timeout=120s

# Show status
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "Status:"
kubectl -n todo-app get pods,svc,ingress

echo ""
echo -e "${GREEN}🎉 Application deployed successfully!${NC}"
echo "Access the application at: http://todo-${ENV}.local"