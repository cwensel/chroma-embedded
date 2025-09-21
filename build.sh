#!/bin/bash

# Build Enhanced ChromaDB Docker Image with Multiple Embedding Models
# This script builds a custom ChromaDB image with Stella, ModernBERT, and BGE-Large models pre-installed

set -e

# Configuration
IMAGE_NAME="chromadb-enhanced"
IMAGE_TAG="latest"
DOCKERFILE="Dockerfile"

echo "🔨 Building Enhanced ChromaDB Docker Image"
echo "=========================================="
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Dockerfile: ${DOCKERFILE}"
echo ""

# Verify Dockerfile exists
if [ ! -f "$DOCKERFILE" ]; then
    echo "❌ Dockerfile not found: $DOCKERFILE"
    exit 1
fi

echo "📦 Starting Docker build (this may take 10-15 minutes)..."
echo "⏳ Downloading models: Stella-400m, ModernBERT-large, BGE-Large"
echo ""

# Build the Docker image
docker build \
    --no-cache \
    --progress=plain \
    -f "$DOCKERFILE" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    .

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Enhanced ChromaDB image built successfully!"
    echo ""
    echo "📋 Image Details:"
    docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    echo ""
    echo "🚀 Ready to run with:"
    echo "   ./server.sh"
    echo ""
    echo "📚 Available embedding models:"
    echo "   • stella (Stella-400m) - Top MTEB performer"
    echo "   • modernbert (ModernBERT-large) - Latest state-of-the-art"
    echo "   • bge-large (BGE-Large) - Production proven"
else
    echo "❌ Docker build failed!"
    exit 1
fi