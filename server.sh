#!/bin/bash

# Run Enhanced ChromaDB Docker Container with Multiple Embedding Models
# This script starts the enhanced ChromaDB server with configurable embedding models

set -e

# Default configuration
IMAGE_NAME="chromadb-enhanced"
IMAGE_TAG="latest"
CONTAINER_NAME="chromadb-enhanced"
HOST_PORT="8000"
CONTAINER_PORT="8000"
DATA_DIR="./chroma_data"
MODELS_CACHE="./models_cache"
EMBEDDING_MODEL="stella"  # Default to Stella-400m

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -m, --model MODEL        Embedding model (stella|modernbert|bge-large) [default: stella]"
    echo "  -p, --port PORT          Host port [default: 8000]"
    echo "  -d, --data-dir PATH      Data directory for persistence [default: ./chroma_data]"
    echo "  -c, --cache-dir PATH     Models cache directory [default: ./models_cache]"
    echo "  --container-name NAME    Docker container name [default: chromadb-enhanced]"
    echo "  --stop                   Stop the running container"
    echo "  --restart                Restart the container with new settings"
    echo "  --logs                   Show container logs"
    echo "  --help                   Show this help message"
    echo ""
    echo "Available embedding models:"
    echo "  stella      - Stella-400m (Top MTEB performer, 1024 dims)"
    echo "  modernbert  - ModernBERT-large (Latest state-of-the-art, 1024 dims)"
    echo "  bge-large   - BGE-Large (Production proven, 1024 dims)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Start with Stella model"
    echo "  $0 -m modernbert -p 8001             # Start with ModernBERT on port 8001"
    echo "  $0 --stop                            # Stop the container"
    echo "  $0 --restart -m bge-large            # Restart with BGE-Large model"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--model)
            EMBEDDING_MODEL="$2"
            shift 2
            ;;
        -p|--port)
            HOST_PORT="$2"
            shift 2
            ;;
        -d|--data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        -c|--cache-dir)
            MODELS_CACHE="$2"
            shift 2
            ;;
        --container-name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --stop)
            echo "🛑 Stopping ChromaDB container..."
            docker stop "$CONTAINER_NAME" 2>/dev/null || echo "Container not running"
            docker rm "$CONTAINER_NAME" 2>/dev/null || echo "Container not found"
            echo "✅ Container stopped and removed"
            exit 0
            ;;
        --restart)
            echo "🔄 Restarting ChromaDB container..."
            docker stop "$CONTAINER_NAME" 2>/dev/null || true
            docker rm "$CONTAINER_NAME" 2>/dev/null || true
            shift
            ;;
        --logs)
            echo "📋 Showing ChromaDB container logs..."
            docker logs -f "$CONTAINER_NAME"
            exit 0
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate embedding model
case $EMBEDDING_MODEL in
    stella|modernbert|bge-large)
        ;;
    *)
        echo "❌ Invalid embedding model: $EMBEDDING_MODEL"
        echo "Valid options: stella, modernbert, bge-large"
        exit 1
        ;;
esac

# Check if image exists
if ! docker images "${IMAGE_NAME}:${IMAGE_TAG}" | grep -q "$IMAGE_NAME"; then
    echo "❌ Enhanced ChromaDB image not found: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "💡 Build it first with: ./build.sh"
    exit 1
fi

# Create directories if they don't exist
mkdir -p "$DATA_DIR"
mkdir -p "$MODELS_CACHE"

# Convert relative paths to absolute paths
DATA_DIR=$(realpath "$DATA_DIR")
MODELS_CACHE=$(realpath "$MODELS_CACHE")

echo "🚀 Starting Enhanced ChromaDB Server"
echo "===================================="
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Container: $CONTAINER_NAME"
echo "Port: $HOST_PORT"
echo "Embedding Model: $EMBEDDING_MODEL"
echo "Data Directory: $DATA_DIR"
echo "Models Cache: $MODELS_CACHE"
echo ""

# Stop existing container if running
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo "🔄 Stopping existing container..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
fi

# Run the container
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    -v "${DATA_DIR}:/chroma/data" \
    -v "${MODELS_CACHE}:/models" \
    -e CHROMA_EMBEDDING_MODEL="$EMBEDDING_MODEL" \
    -e TRANSFORMERS_CACHE="/models" \
    -e HF_HOME="/models" \
    "${IMAGE_NAME}:${IMAGE_TAG}"

# Wait a moment for container to start
sleep 3

# Check if container is running
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo "✅ ChromaDB Enhanced server started successfully!"
    echo ""
    echo "📊 Container Status:"
    docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "🔗 Server Endpoints:"
    echo "   HTTP API: http://localhost:$HOST_PORT"
    echo "   Health: http://localhost:$HOST_PORT/api/v2/heartbeat"
    echo ""
    echo "📋 Useful Commands:"
    echo "   View logs: $0 --logs"
    echo "   Stop: $0 --stop"
    echo "   Restart: $0 --restart -m <model>"
    echo ""
    echo "🧪 Test connection:"
    echo "   curl http://localhost:$HOST_PORT/api/v2/heartbeat"

    # Test the heartbeat endpoint
    echo ""
    echo "🏥 Testing server health..."
    sleep 2
    if curl -s "http://localhost:$HOST_PORT/api/v2/heartbeat" > /dev/null; then
        echo "✅ Server is responding to health checks"
    else
        echo "⚠️  Server may still be starting up. Check logs with: $0 --logs"
    fi
else
    echo "❌ Failed to start container. Check logs with:"
    echo "   docker logs $CONTAINER_NAME"
    exit 1
fi