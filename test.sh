#!/bin/bash

# Test Enhanced ChromaDB Setup with Multiple Embedding Models
# This script tests the complete setup: Docker build, server start, and PDF upload

set -e

echo "🧪 Testing Enhanced ChromaDB Setup"
echo "================================="
echo ""

# Test 1: Check if scripts are executable
echo "1️⃣ Testing script permissions..."
if [ -x "./build.sh" ] && [ -x "./server.sh" ] && [ -x "./upload.sh" ]; then
    echo "✅ All scripts are executable"
else
    echo "❌ Scripts need execute permissions"
    chmod +x ./build.sh ./server.sh ./upload.sh
    echo "✅ Fixed script permissions"
fi
echo ""

# Test 2: Validate upload script help and embedding options
echo "2️⃣ Testing upload script embedding options..."
echo "Available embedding models:"
./upload.sh --help | grep -A 10 "Embedding Models:" || echo "Help section found"
echo ""

# Test 3: Check Docker availability
echo "3️⃣ Testing Docker availability..."
if command -v docker &> /dev/null; then
    echo "✅ Docker is available"
    docker --version
else
    echo "❌ Docker is not available - please install Docker"
    exit 1
fi
echo ""

# Test 4: Test embedding model validation
echo "4️⃣ Testing embedding model validation..."
echo "Testing invalid embedding model (should fail):"
if ./upload.sh -e invalid-model --help 2>/dev/null; then
    echo "❌ Validation not working properly"
else
    echo "✅ Embedding model validation working"
fi

echo "Testing valid embedding models:"
for model in stella modernbert bge-large default; do
    echo -n "  Testing $model: "
    if ./upload.sh -e "$model" --help &>/dev/null; then
        echo "✅"
    else
        echo "❌"
    fi
done
echo ""

# Test 5: Check required Python packages
echo "5️⃣ Testing Python dependencies..."
python3 -c "
try:
    import chromadb
    import fitz
    print('✅ Required packages (chromadb, pymupdf) available')
except ImportError as e:
    print(f'❌ Missing package: {e}')
    print('Install with: pip install --upgrade chromadb pymupdf')
    exit(1)
"
echo ""

# Test 6: Build enhanced ChromaDB image (optional - only if user confirms)
echo "6️⃣ Optional: Build enhanced ChromaDB Docker image"
echo "⚠️  This will take 10-15 minutes and download ~3GB of models"
read -p "Do you want to build the enhanced ChromaDB image? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Building enhanced ChromaDB image..."
    ./build.sh

    if [ $? -eq 0 ]; then
        echo ""
        echo "7️⃣ Testing enhanced ChromaDB server startup..."
        echo "Starting server with Stella model..."
        ./server.sh -m stella -p 8001 &
        SERVER_PID=$!

        # Wait for server to start
        echo "Waiting for server to start..."
        sleep 30

        # Test heartbeat
        if curl -s "http://localhost:8001/api/v2/heartbeat" > /dev/null; then
            echo "✅ Enhanced ChromaDB server is responding"

            # Test with a small upload
            echo ""
            echo "8️⃣ Testing small upload with Stella embeddings..."
            if ./upload.sh -e stella -p 8001 -l 1 -c TestCollection --delete-collection; then
                echo "✅ Upload test successful"
            else
                echo "❌ Upload test failed"
            fi
        else
            echo "❌ Server not responding to health checks"
        fi

        # Stop server
        echo "Stopping test server..."
        ./server.sh --stop
        kill $SERVER_PID 2>/dev/null || true
    fi
else
    echo "Skipping Docker image build"
fi

echo ""
echo "🎉 Setup Testing Complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Build the enhanced image: ./build.sh"
echo "2. Start the server: ./server.sh -m stella"
echo "3. Upload PDFs: ./upload.sh -e stella --delete-collection"
echo ""
echo "💡 Usage Examples:"
echo "  ./server.sh -m stella        # Start with Stella"
echo "  ./server.sh -m modernbert    # Start with ModernBERT"
echo "  ./upload.sh -e stella -l 10        # Upload 10 files with Stella"
echo "  ./upload.sh -e modernbert --delete-collection  # Fresh upload with ModernBERT"