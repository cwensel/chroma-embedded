# Adding New Embedding Models

This guide shows how to add new embedding models to the ChromaDB Enhanced setup using Claude Code.

## Quick Commands for Claude

When working with Claude Code, use these exact commands:

### Add a New Model
```bash
# 1. Update Dockerfile to include new model
./build.sh

# 2. Test the model with different store types
./upload.sh --store pdf -e new-model-name -l 1 -c TestPDF --delete-collection
./upload.sh --store source-code -e new-model-name -l 1 -c TestCode --delete-collection
./upload.sh --store documentation -e new-model-name -l 1 -c TestDocs --delete-collection

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

# Test upload with different store types
./upload.sh --store pdf -e mpnet -i /path/to/test/pdfs -l 1 -c TestModelPDF --delete-collection
./upload.sh --store source-code -e mpnet -i /path/to/test/source -l 1 -c TestModelCode --delete-collection
./upload.sh --store documentation -e mpnet -i /path/to/test/docs -l 1 -c TestModelDocs --delete-collection

# Verify collections
curl "http://localhost:9000/api/v2/collections/TestModelPDF"
curl "http://localhost:9000/api/v2/collections/TestModelCode"
curl "http://localhost:9000/api/v2/collections/TestModelDocs"
```

## Git Project-Aware Source Code Processing

### Quick Git Project Commands
```bash
# Index git projects with automatic change detection
./upload.sh --store source-code -i /workspace -c DevCode -e stella

# Only scan direct subdirectories for git projects (faster for organized workspaces)
./upload.sh --store source-code -i /workspace --depth 1 -c MainProjects -e stella

# Re-run same command - only processes projects with changed commits
./upload.sh --store source-code -i /workspace -c DevCode -e stella

# Test with specific project
./upload.sh --store source-code -i /path/to/git/project -c TestProject --delete-collection -e stella
```

### Git Project Features
- **Automatic Discovery**: Finds `.git` directories automatically
- **Smart Updates**: Only re-processes projects when git commit changes
- **Respects .gitignore**: Uses `git ls-files` to filter files
- **Project Metadata**: Each chunk includes git project name, commit hash, remote URL
- **Depth Control**: `--depth N` limits how deep to search for nested projects

### Testing Git Features
```bash
# Test depth parameter
./upload.sh --store source-code -i /workspace --depth 1 -c Depth1Test -e stella --delete-collection
./upload.sh --store source-code -i /workspace --depth 2 -c Depth2Test -e stella --delete-collection
./upload.sh --store source-code -i /workspace -c UnlimitedTest -e stella --delete-collection

# Compare results
python3 -c "
import chromadb
client = chromadb.HttpClient(host='localhost', port=9000)
for collection_name in ['Depth1Test', 'Depth2Test', 'UnlimitedTest']:
    collection = client.get_collection(collection_name)
    print(f'{collection_name}: {collection.count()} documents')

    # Show unique projects
    docs = collection.get(include=['metadatas'], limit=100)
    projects = set(m.get('git_project_name', 'unknown') for m in docs['metadatas'])
    print(f'  Projects: {sorted(projects)}')
    print()
"
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

| Use Case | Recommended Model | Dimensions | Speed | Store Type |
|----------|------------------|------------|--------|------------|
| Research papers | stella | 1024 | Medium | pdf |
| Source code projects | stella | 1024 | Medium | source-code |
| API documentation | stella | 1024 | Medium | documentation |
| General text | mpnet | 768 | Fast | pdf, documentation |
| Latest tech docs | modernbert | 1024 | Medium | pdf, documentation |
| Production workloads | bge-large | 1024 | Fast | all |
| Quick testing | default | 384 | Fastest | all |

### Git Project Scenarios
- **Large codebases**: Use `stella` with `--depth 1` for main projects only
- **Multi-language repos**: Use `stella` for best cross-language understanding
- **Incremental updates**: Any model works - git change detection handles efficiency