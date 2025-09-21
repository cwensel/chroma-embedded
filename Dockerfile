FROM python:3.11-slim

# Set working directory
WORKDIR /chroma

# Install ChromaDB and Python dependencies
RUN pip install --no-cache-dir \
    chromadb>=0.5.0 \
    sentence-transformers==5.1.0 \
    torch>=2.0.0 \
    transformers>=4.41.0

# Create model cache directory
RUN mkdir -p /models
ENV TRANSFORMERS_CACHE=/models
ENV HF_HOME=/models

# Pre-download embedding models to avoid runtime delays
RUN python3 -c "\
import os; \
os.environ['TRANSFORMERS_CACHE'] = '/models'; \
os.environ['HF_HOME'] = '/models'; \
from sentence_transformers import SentenceTransformer; \
print('Downloading embedding models...'); \
stella = SentenceTransformer('dunzhang/stella_en_400M_v5', trust_remote_code=True); \
print(f'✓ Stella-400m loaded: {stella.get_sentence_embedding_dimension()} dimensions'); \
modernbert = SentenceTransformer('answerdotai/ModernBERT-large', trust_remote_code=True); \
print(f'✓ ModernBERT-large loaded: {modernbert.get_sentence_embedding_dimension()} dimensions'); \
bge = SentenceTransformer('BAAI/bge-large-en-v1.5'); \
print(f'✓ BGE-Large loaded: {bge.get_sentence_embedding_dimension()} dimensions'); \
print('All embedding models downloaded successfully!')"

# Create custom embedding functions module
RUN python3 -c "\
import os; \
os.environ['TRANSFORMERS_CACHE'] = '/models'; \
os.environ['HF_HOME'] = '/models'; \
embedding_code = '''from chromadb import Documents, EmbeddingFunction, Embeddings\nfrom sentence_transformers import SentenceTransformer\nimport os\n\nclass StellaEmbeddingFunction(EmbeddingFunction[Documents]):\n    def __init__(self):\n        self.model = SentenceTransformer(\"dunzhang/stella_en_400M_v5\", trust_remote_code=True)\n\n    def __call__(self, input: Documents) -> Embeddings:\n        return self.model.encode(input).tolist()\n\nclass ModernBERTEmbeddingFunction(EmbeddingFunction[Documents]):\n    def __init__(self):\n        self.model = SentenceTransformer(\"answerdotai/ModernBERT-large\", trust_remote_code=True)\n\n    def __call__(self, input: Documents) -> Embeddings:\n        return self.model.encode(input).tolist()\n\nclass BGEEmbeddingFunction(EmbeddingFunction[Documents]):\n    def __init__(self):\n        self.model = SentenceTransformer(\"BAAI/bge-large-en-v1.5\")\n\n    def __call__(self, input: Documents) -> Embeddings:\n        return self.model.encode(input).tolist()\n\ndef get_embedding_function(model_name: str):\n    model_map = {\n        \"stella\": StellaEmbeddingFunction,\n        \"modernbert\": ModernBERTEmbeddingFunction,\n        \"bge-large\": BGEEmbeddingFunction\n    }\n    if model_name not in model_map:\n        raise ValueError(f\"Unknown embedding model: {model_name}. Available: {list(model_map.keys())}\")\n    return model_map[model_name]()\n'''; \
with open('/chroma/embedding_functions.py', 'w') as f: f.write(embedding_code); \
print('Custom embedding functions created')"

# Set environment variables
ENV CHROMA_EMBEDDING_MODEL=stella
ENV CHROMA_SERVER_HOST=0.0.0.0
ENV CHROMA_SERVER_HTTP_PORT=8000
ENV IS_PERSISTENT=1

# Add the embedding functions to Python path
ENV PYTHONPATH=/chroma

# Create startup script that validates models
RUN echo '#!/bin/bash\necho "Starting Enhanced ChromaDB Server..."\necho "Available embedding models: stella, modernbert, bge-large"\necho "Current model: $CHROMA_EMBEDDING_MODEL"\necho ""\npython3 -c "import sys; sys.path.insert(0, \\"/chroma\\"); from embedding_functions import get_embedding_function; get_embedding_function(\\"stella\\"); print(\\"✓ Stella model validated\\"); get_embedding_function(\\"modernbert\\"); print(\\"✓ ModernBERT model validated\\"); get_embedding_function(\\"bge-large\\"); print(\\"✓ BGE-Large model validated\\"); print(\\"All embedding models ready!\\")"\necho "Starting ChromaDB server..."\nexec "$@"' > /chroma/start-enhanced-chroma.sh

RUN chmod +x /chroma/start-enhanced-chroma.sh

# Expose port
EXPOSE 8000

# Use custom startup script
ENTRYPOINT ["/chroma/start-enhanced-chroma.sh"]
CMD ["chroma", "run", "--host", "0.0.0.0", "--port", "8000", "--path", "/chroma/data"]