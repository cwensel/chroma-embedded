# Stage 1: Builder - Install dependencies only
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies for xformers
RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Install embedding dependencies and ChromaDB
# Use specific xformers version that has pre-built wheels
RUN pip install --no-cache-dir \
    chromadb>=0.5.0 \
    sentence-transformers==5.1.0 \
    torch>=2.0.0 \
    transformers>=4.41.0 \
    "xformers>=0.0.20"

# Copy embedding functions file
COPY embedding_functions.py /build/embedding_functions.py

# Stage 2: Runtime - ChromaDB base with our enhancements
FROM chromadb/chroma:latest

# Install missing system dependencies for PyTorch/transformers
RUN apt-get update && apt-get install -y \
    libffi8 \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy Python executable, libraries and dependencies from builder
COPY --from=builder /usr/local/bin/python* /usr/local/bin/
COPY --from=builder /usr/local/lib/python3.11 /usr/local/lib/python3.11
COPY --from=builder /usr/local/lib/libpython3.11.so* /usr/local/lib/
COPY --from=builder /build/embedding_functions.py /chroma/embedding_functions.py

# Set environment variables for external model cache
ENV TRANSFORMERS_CACHE=/models
ENV HF_HOME=/models
ENV SENTENCE_TRANSFORMERS_HOME=/models
ENV CHROMA_EMBEDDING_MODEL=stella

# Add embedding functions to Python path
ENV PYTHONPATH=/chroma

# Create enhanced entrypoint script
RUN echo '#!/bin/bash\n\
echo "Enhanced ChromaDB Server with External Model Cache"\n\
echo "================================================"\n\
echo "Available models: stella, modernbert, bge-large"\n\
echo "Current model: $CHROMA_EMBEDDING_MODEL"\n\
echo "Model cache: $TRANSFORMERS_CACHE"\n\
echo ""\n\
\n\
# Ensure model cache directory exists\n\
mkdir -p /models\n\
\n\
# Check if we have python available for model downloads\n\
if command -v python3 >/dev/null 2>&1; then\n\
    echo "Python available - models will be downloaded on first use"\n\
    # Test that embedding functions can be imported\n\
    python3 -c "import sys; sys.path.insert(0, \"/chroma\"); import embedding_functions; print(\"✓ Embedding functions ready\")" 2>/dev/null || echo "⚠️  Embedding functions may not be available"\n\
else\n\
    echo "⚠️  Python not found - using ChromaDB default embeddings"\n\
fi\n\
\n\
echo "Starting ChromaDB server..."\n\
exec "$@"\n\
' > /chroma/enhanced-entrypoint.sh

RUN chmod +x /chroma/enhanced-entrypoint.sh

# Create smart model download script
RUN echo '#!/bin/bash\n\
echo "Enhanced ChromaDB Server with On-Demand Model Downloads"\n\
echo "====================================================="\n\
echo "Available models: stella, modernbert, bge-large, default"\n\
echo "Requested model: $CHROMA_EMBEDDING_MODEL"\n\
echo "Model cache: $TRANSFORMERS_CACHE"\n\
echo ""\n\
\n\
# Ensure model cache directory exists\n\
mkdir -p /models\n\
\n\
# Check if Python is available for model downloads\n\
if ! command -v python3 >/dev/null 2>&1; then\n\
    echo "⚠️  Python not found - using ChromaDB default embeddings"\n\
    echo "Starting ChromaDB server..."\n\
    exec dumb-init -- chroma "$@"\n\
fi\n\
\n\
echo "✓ Python available for enhanced embeddings"\n\
\n\
# Define model mappings\n\
case "$CHROMA_EMBEDDING_MODEL" in\n\
    stella)\n\
        MODEL_NAME="dunzhang/stella_en_400M_v5"\n\
        MODEL_ARGS="trust_remote_code=True"\n\
        ;;\n\
    modernbert)\n\
        MODEL_NAME="answerdotai/ModernBERT-large"\n\
        MODEL_ARGS="trust_remote_code=True"\n\
        ;;\n\
    bge-large)\n\
        MODEL_NAME="BAAI/bge-large-en-v1.5"\n\
        MODEL_ARGS=""\n\
        ;;\n\
    default|"")\n\
        echo "Using ChromaDB default embeddings"\n\
        echo "Starting ChromaDB server..."\n\
        exec dumb-init -- chroma "$@"\n\
        ;;\n\
    *)\n\
        echo "❌ Unknown model: $CHROMA_EMBEDDING_MODEL"\n\
        echo "Available: stella, modernbert, bge-large, default"\n\
        exit 1\n\
        ;;\n\
esac\n\
\n\
echo "Checking model: $CHROMA_EMBEDDING_MODEL ($MODEL_NAME)"\n\
\n\
# Check if model is already cached by examining directory structure\n\
MODEL_DIR=\"/models/models--$(echo $MODEL_NAME | tr '/' '--')\"\n\
if [ -d \"$MODEL_DIR\" ] && [ \"$(ls -A $MODEL_DIR 2>/dev/null)\" ]; then\n\
    MODEL_CACHED=\"cached\"\n\
else\n\
    MODEL_CACHED=\"missing\"\n\
fi\n\
\n\
if [ "$MODEL_CACHED" = "cached" ]; then\n\
    echo "✓ Model $CHROMA_EMBEDDING_MODEL already cached"\n\
else\n\
    echo "⬇️  Downloading model $CHROMA_EMBEDDING_MODEL..."\n\
    echo "This may take 2-5 minutes depending on model size"\n\
    python3 -c "\
import os, sys\n\
sys.path.insert(0, \"/chroma\")\n\
from sentence_transformers import SentenceTransformer\n\
print(\"Downloading $MODEL_NAME...\")\n\
model = SentenceTransformer(\"$MODEL_NAME\", cache_folder=\"/models\", $MODEL_ARGS)\n\
dims = model.get_sentence_embedding_dimension()\n\
print(f\"✓ $CHROMA_EMBEDDING_MODEL ready ({dims} dimensions)\")\n\
    "\n\
fi\n\
\n\
# Verify embedding functions work\n\
echo "Testing embedding functions..."\n\
python3 -c "\
import sys\n\
sys.path.insert(0, \"/chroma\")\n\
try:\n\
    import embedding_functions\n\
    ef = embedding_functions.get_embedding_function(\"$CHROMA_EMBEDDING_MODEL\")\n\
    print(\"✓ Embedding functions ready for $CHROMA_EMBEDDING_MODEL\")\n\
except Exception as e:\n\
    print(f\"⚠️  Embedding function test failed: {e}\")\n\
"\n\
\n\
echo ""\n\
echo "Starting ChromaDB server with $CHROMA_EMBEDDING_MODEL embeddings..."\n\
exec dumb-init -- chroma "$@"\n\
' > /chroma/enhanced-init.sh && chmod +x /chroma/enhanced-init.sh

# Use enhanced init script that preserves ChromaDB entrypoint
ENTRYPOINT ["/chroma/enhanced-init.sh"]
CMD ["run", "/config.yaml"]