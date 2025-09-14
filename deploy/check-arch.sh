#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Architecture Check Script ===${NC}"
echo ""

# Check local architecture
echo -e "${GREEN}Local Machine Architecture:${NC}"
echo -n "  OS: "
uname -s
echo -n "  Architecture: "
uname -m
echo -n "  Docker platform: "
if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "linux/amd64"
elif [[ "$(uname -m)" == "aarch64" ]] || [[ "$(uname -m)" == "arm64" ]]; then
    echo "linux/arm64"
else
    echo "$(uname -m)"
fi
echo ""

# Check Docker buildx availability
echo -e "${GREEN}Docker Buildx Status:${NC}"
if docker buildx version &>/dev/null; then
    echo "  ✅ Docker buildx is available"
    echo -n "  Version: "
    docker buildx version | head -1
    
    # Check current builder
    echo ""
    echo -e "${GREEN}Current Builder:${NC}"
    docker buildx ls | grep -E "^\*" || echo "  No active builder"
else
    echo -e "  ${RED}❌ Docker buildx is not available${NC}"
    echo "  Please update Docker Desktop or install buildx plugin"
fi
echo ""

# Check remote node architecture (if kubectl is available and configured)
if kubectl version --client &>/dev/null; then
    echo -e "${GREEN}Kubernetes Node Architecture:${NC}"
    
    # Check if we can connect to cluster
    if kubectl get nodes &>/dev/null; then
        kubectl get nodes -o wide | awk 'NR==1 || /Ready/' | awk '{print "  "$1": "$11}'
    else
        echo -e "  ${YELLOW}⚠️  Cannot connect to Kubernetes cluster${NC}"
    fi
else
    echo -e "${YELLOW}kubectl not available - skipping node architecture check${NC}"
fi
echo ""

# Check image architecture (if image exists)
if [ -f "deploy/.env" ]; then
    source deploy/.env
    IMAGE="${DOCKER_REGISTRY}/${DOCKER_USER}/${APP_NAME}:${IMAGE_TAG}"
    
    echo -e "${GREEN}Docker Image Architecture for ${IMAGE}:${NC}"
    
    # Try to inspect the image
    if docker manifest inspect "${IMAGE}" &>/dev/null; then
        echo "  Available platforms:"
        docker manifest inspect "${IMAGE}" 2>/dev/null | \
            grep -A 2 '"platform"' | \
            grep -E '"architecture"|"os"' | \
            sed 's/.*: "\(.*\)".*/  - \1/' | \
            paste -d'/' - - | \
            sed 's/^  - /  - /'
    else
        echo -e "  ${YELLOW}Image not found or not accessible${NC}"
        echo "  Try: docker pull ${IMAGE}"
    fi
fi
echo ""

echo -e "${BLUE}=== Recommendations ===${NC}"
echo ""

# Provide recommendations based on architecture
LOCAL_ARCH=$(uname -m)
if [[ "$LOCAL_ARCH" == "x86_64" ]]; then
    echo "• Your local machine is x86_64 (amd64)"
    echo "• If k3s nodes are ARM64, use multi-arch build:"
    echo -e "  ${GREEN}make deploy${NC}  # This will build for both amd64 and arm64"
elif [[ "$LOCAL_ARCH" == "aarch64" ]] || [[ "$LOCAL_ARCH" == "arm64" ]]; then
    echo "• Your local machine is ARM64"
    echo "• If k3s nodes are x86_64, use multi-arch build:"
    echo -e "  ${GREEN}make deploy${NC}  # This will build for both amd64 and arm64"
else
    echo "• Unknown architecture: $LOCAL_ARCH"
    echo "• Use multi-arch build to be safe:"
    echo -e "  ${GREEN}make deploy${NC}"
fi

echo ""
echo -e "${BLUE}Common issues:${NC}"
echo "• exec format error → Architecture mismatch"
echo "• Solution: Use 'make deploy' for multi-arch build"
echo ""