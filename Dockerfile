FROM chromadb/chroma:latest

# Set working directory
WORKDIR /chroma

# Install Python dependencies
RUN pip install --no-cache-dir \
    sentence-transformers==5.1.0 \
    torch>=2.0.0 \
    transformers>=4.41.0

# Create model cache directory
RUN mkdir -p /models
ENV TRANSFORMERS_CACHE=/models
ENV HF_HOME=/models

# Pre-download embedding models to avoid runtime delays
RUN python3 -c "
import os
os.environ['TRANSFORMERS_CACHE'] = '/models'
os.environ['HF_HOME'] = '/models'

from sentence_transformers import SentenceTransformer
print('Downloading embedding models...')

try:
    # 1. Stella-400m (Top MTEB performer)
    print('Downloading Stella-400m...')
    stella = SentenceTransformer('dunzhang/stella_en_400M_v5', trust_remote_code=True)
    print(f'✓ Stella-400m loaded: {stella.get_sentence_embedding_dimension()} dimensions')

    # 2. ModernBERT-large (Latest state-of-the-art)
    print('Downloading ModernBERT-large...')
    modernbert = SentenceTransformer('answerdotai/ModernBERT-large', trust_remote_code=True)
    print(f'✓ ModernBERT-large loaded: {modernbert.get_sentence_embedding_dimension()} dimensions')

    # 3. BGE-Large (Production proven)
    print('Downloading BGE-Large...')
    bge = SentenceTransformer('BAAI/bge-large-en-v1.5')
    print(f'✓ BGE-Large loaded: {bge.get_sentence_embedding_dimension()} dimensions')

    print('All embedding models downloaded successfully!')

except Exception as e:
    print(f'Error downloading models: {e}')
    exit(1)
"

# Create custom embedding functions module
RUN python3 -c "
import os
os.environ['TRANSFORMERS_CACHE'] = '/models'
os.environ['HF_HOME'] = '/models'

# Create embedding functions module
embedding_code = '''
from chromadb import Documents, EmbeddingFunction, Embeddings
from sentence_transformers import SentenceTransformer
import os

class StellaEmbeddingFunction(EmbeddingFunction[Documents]):
    def __init__(self):
        self.model = SentenceTransformer(\"dunzhang/stella_en_400M_v5\", trust_remote_code=True)

    def __call__(self, input: Documents) -> Embeddings:
        return self.model.encode(input).tolist()

class ModernBERTEmbeddingFunction(EmbeddingFunction[Documents]):
    def __init__(self):
        self.model = SentenceTransformer(\"answerdotai/ModernBERT-large\", trust_remote_code=True)

    def __call__(self, input: Documents) -> Embeddings:
        return self.model.encode(input).tolist()

class BGEEmbeddingFunction(EmbeddingFunction[Documents]):
    def __init__(self):
        self.model = SentenceTransformer(\"BAAI/bge-large-en-v1.5\")

    def __call__(self, input: Documents) -> Embeddings:
        return self.model.encode(input).tolist()

# Function to get embedding function by name
def get_embedding_function(model_name: str):
    model_map = {
        \"stella\": StellaEmbeddingFunction,
        \"modernbert\": ModernBERTEmbeddingFunction,
        \"bge-large\": BGEEmbeddingFunction
    }

    if model_name not in model_map:
        raise ValueError(f\"Unknown embedding model: {model_name}. Available: {list(model_map.keys())}\")

    return model_map[model_name]()
'''

# Write the embedding functions to a file
with open('/chroma/embedding_functions.py', 'w') as f:
    f.write(embedding_code)

print('Custom embedding functions created')
"

# Set environment variables
ENV CHROMA_EMBEDDING_MODEL=stella
ENV CHROMA_SERVER_HOST=0.0.0.0
ENV CHROMA_SERVER_HTTP_PORT=8000
ENV IS_PERSISTENT=1

# Add the embedding functions to Python path
ENV PYTHONPATH=/chroma:$PYTHONPATH

# Create startup script that validates models
RUN echo '#!/bin/bash
echo "Starting Enhanced ChromaDB Server..."
echo "Available embedding models: stella, modernbert, bge-large"
echo "Current model: $CHROMA_EMBEDDING_MODEL"
echo ""

# Validate that models are accessible
python3 -c "
import sys
sys.path.insert(0, \"/chroma\")
try:
    from embedding_functions import get_embedding_function
    ef = get_embedding_function(\"stella\")
    print(\"✓ Stella model validated\")
    ef = get_embedding_function(\"modernbert\")
    print(\"✓ ModernBERT model validated\")
    ef = get_embedding_function(\"bge-large\")
    print(\"✓ BGE-Large model validated\")
    print(\"All embedding models ready!\")
except Exception as e:
    print(f\"Error validating models: {e}\")
    exit(1)
"

echo "Starting ChromaDB server..."
exec "$@"
' > /chroma/start-enhanced-chroma.sh

RUN chmod +x /chroma/start-enhanced-chroma.sh

# Expose port
EXPOSE 8000

# Use custom startup script
ENTRYPOINT ["/chroma/start-enhanced-chroma.sh"]
CMD ["chroma", "run", "--host", "0.0.0.0", "--port", "8000", "--path", "/chroma/data"]