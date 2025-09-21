# Adding New Embedding Models

This guide shows how to add new embedding models to the ChromaDB Enhanced setup using Claude Code.

## Quick Commands for Claude

When working with Claude Code, use these exact commands:

### Add a New Model
```bash
# 1. Update Dockerfile to include new model
./build.sh

# 2. Test the model
./upload.sh -e new-model-name -l 1 -c TestCollection --delete-collection

# 3. Run tests
./test.sh
```

### Essential Files to Modify

1. **Dockerfile** - Add model download commands
2. **server.sh** - Add model validation and configuration
3. **upload.sh** - Add model to valid options list
4. **README.md** - Update model comparison table

## Step-by-Step Model Addition

### 1. Research the Model

Find the model on Hugging Face and note:
- Model name (e.g., `sentence-transformers/all-mpnet-base-v2`)
- Dimensions (e.g., 768)
- Best use case (e.g., "General purpose", "Code search")

### 2. Update Dockerfile

Add model download in the pre-loading section:
```dockerfile
# Pre-load new model
RUN python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/all-mpnet-base-v2')"
```

### 3. Update server.sh

Add to model validation:
```bash
validate_model() {
    case "$1" in
        stella|modernbert|bge-large|mpnet|default)
            return 0
            ;;
        *)
            echo "❌ Invalid model: $1"
            echo "Valid models: stella, modernbert, bge-large, mpnet, default"
            return 1
            ;;
    esac
}
```

Add to model mapping:
```bash
case "$EMBEDDING_MODEL" in
    mpnet)
        export CHROMA_EMBEDDING_MODEL="sentence-transformers/all-mpnet-base-v2"
        ;;
esac
```

### 4. Update upload.sh

Add to valid models list:
```bash
validate_embedding_model() {
    case "$1" in
        stella|modernbert|bge-large|mpnet|default)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
```

Add to help text:
```bash
echo "  mpnet         - All-MiniLM-L12-v2 (768 dims, general purpose)"
```

### 5. Update README.md

Add to model comparison table:
```markdown
| **mpnet** | 768 | General purpose text | 🚀 Fast, reliable |
```

## Testing New Models

```bash
# Build with new model
./build.sh

# Start server
./server.sh -m mpnet

# Test upload
./upload.sh -e mpnet -i /path/to/test/pdfs -l 1 -c TestModel --delete-collection

# Verify collection
curl "http://localhost:8000/api/v2/collections/TestModel"
```

## Common Model Types

### Sentence Transformers Format
```python
# In Dockerfile
RUN python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('model-name')"

# In server environment
CHROMA_EMBEDDING_MODEL="model-name"
```

### Hugging Face Transformers Format
```python
# In Dockerfile
RUN python3 -c "from transformers import AutoModel; AutoModel.from_pretrained('model-name')"

# May need additional ChromaDB embedding function wrapper
```

## Troubleshooting

### Model Won't Load
- Check model name spelling
- Verify model exists on Hugging Face
- Ensure sufficient Docker memory (8GB+)
- Check network connectivity for downloads

### Performance Issues
- Monitor Docker memory usage
- Consider model size vs performance trade-offs
- Test with small batches first

### Validation Errors
- Ensure model name added to all validation functions
- Check case sensitivity in model names
- Verify help text matches actual options

## Model Recommendations

| Use Case | Recommended Model | Dimensions | Speed |
|----------|------------------|------------|--------|
| Research papers | stella | 1024 | Medium |
| General text | mpnet | 768 | Fast |
| Latest tech | modernbert | 1024 | Medium |
| Production | bge-large | 1024 | Fast |
| Quick testing | default | 384 | Fastest |