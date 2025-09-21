# ChromaDB Enhanced Embeddings

High-performance ChromaDB server with built-in support for multiple state-of-the-art embedding models, enabling superior semantic search for your PDF research library.

## 🚀 Quick Start

```bash
# 1. Build the enhanced ChromaDB image (10-15 minutes)
./build.sh

# 2. Start server with Stella-400m embeddings
./server.sh -m stella

# 3. Upload PDFs with server-side embeddings (specify your PDF directory)
./upload.sh -i /path/to/your/pdfs -e stella --delete-collection -l 10
```

## 📁 Project Structure

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-model ChromaDB Docker image |
| `build.sh` | Build script for Docker image |
| `server.sh` | Server management script |
| `upload.sh` | PDF upload script with embedding support |
| `test.sh` | Complete setup testing |
| `requirements.txt` | Python dependencies |
| `.gitignore` | Git ignore rules |
| `LICENSE` | MIT license |

## 🎯 Available Embedding Models

| Model | Dimensions | Best For | Performance |
|-------|------------|----------|-------------|
| **stella** | 1024 | Research papers, academic content | 🥇 Top MTEB performer |
| **modernbert** | 1024 | General purpose, latest tech | 🔬 State-of-the-art 2024 |
| **bge-large** | 1024 | Production deployments | 🏭 Battle-tested |
| **default** | 384 | Quick testing, compatibility | ⚡ Fast, lightweight |

## 🔧 Server Management

### Start Server
```bash
# Start with Stella embeddings (recommended)
./server.sh -m stella

# Start with ModernBERT on custom port
./server.sh -m modernbert -p 8001

# Start with BGE-Large for production
./server.sh -m bge-large
```

### Server Operations
```bash
# View logs
./server.sh --logs

# Stop server
./server.sh --stop

# Restart with different model
./server.sh --restart -m modernbert
```

## 📄 PDF Upload Examples

### Basic Upload
```bash
# Upload with Stella embeddings
./upload.sh -i /path/to/pdfs -e stella

# Upload first 5 files only
./upload.sh -i /path/to/pdfs -e stella -l 5

# Fresh collection with ModernBERT
./upload.sh -i /path/to/pdfs -e modernbert --delete-collection
```

### Advanced Options
```bash
# Custom chunking parameters
./upload.sh -i /path/to/pdfs -e stella --chunk-size 2000 --chunk-overlap 400

# Remote server
./upload.sh -i /path/to/pdfs -e stella -h remote-server.com -p 8000

# Custom collection name
./upload.sh -i /path/to/pdfs -e modernbert -c MyResearch --delete-collection

# Using environment variable
PDF_INPUT_PATH=/path/to/pdfs ./upload.sh -e stella
```

## 🏗️ Architecture

```
┌─────────────────┐    HTTP API    ┌──────────────────────┐
│  Upload Client  │───────────────▶│  Enhanced ChromaDB   │
│  (sends text    │                │  Docker Container    │
│   chunks)       │                │  ┌─────────────────┐ │
└─────────────────┘                │  │ ChromaDB Server │ │
                                   │  │ + Stella-400m   │ │
┌─────────────────┐    HTTP API    │  │ + ModernBERT    │ │
│  MCP Client     │───────────────▶│  │ + BGE-Large     │ │
│  (Claude        │                │  │ + SentenceT.    │ │
│   queries)      │                │  └─────────────────┘ │
└─────────────────┘                └──────────────────────┘
```

## 🔄 Migration from Old Setup

### If Currently Using PersistentClient:
1. Build enhanced image: `./build.sh`
2. Start enhanced server: `./server.sh -m stella`
3. Recreate collections: `./upload.sh -i /path/to/pdfs -e stella --delete-collection`
4. Update MCP to use HttpClient pointing to localhost:8000

### Benefits of Migration:
- ✅ **Better embeddings**: Stella-400m vs all-MiniLM-L6-v2
- ✅ **Centralized logic**: One place for embedding models
- ✅ **Model flexibility**: Switch models without client changes
- ✅ **Better performance**: Server-side GPU utilization
- ✅ **Simplified clients**: No local ML dependencies needed

## 🧪 Testing

```bash
# Run comprehensive tests
./test.sh

# Test specific embedding model
./upload.sh -i /path/to/pdfs -e modernbert -l 1 -c TestCollection --delete-collection
```

## 🎛️ Environment Variables

### Server Configuration
```bash
export CHROMA_EMBEDDING_MODEL=stella     # Default embedding model
export TRANSFORMERS_CACHE=/models        # Model cache directory
export HF_HOME=/models                   # HuggingFace cache
```

### Client Configuration
```bash
export PDF_INPUT_PATH=/path/to/pdfs      # Default PDF input directory
export CHROMA_DATA_PATH=/path/to/data    # For PersistentClient mode
```

## 📊 Performance Comparison

| Setup | Embedding Quality | Dimensions | Speed | Complexity |
|-------|-------------------|------------|--------|------------|
| **Old (default)** | Good | 384 | Fast | Low |
| **Enhanced (Stella)** | Excellent | 1024 | Medium | Low |
| **Enhanced (ModernBERT)** | Excellent | 1024 | Medium | Low |
| **Enhanced (BGE-Large)** | Very Good | 1024 | Fast | Low |

## 🔍 Troubleshooting

### Server Won't Start
```bash
# Check Docker
docker ps

# View server logs
./server.sh --logs

# Restart server
./server.sh --restart
```

### Upload Failures
```bash
# Test server connection
curl http://localhost:8000/api/v2/heartbeat

# Check dependencies
python3 -c "import chromadb, fitz; print('✅ Dependencies OK')"

# Use smaller test
./upload.sh -i /path/to/pdfs -e stella -l 1 -c TestCollection --delete-collection
```

### Model Loading Issues
- Ensure Docker has sufficient memory (8GB+ recommended)
- Check network connectivity for model downloads
- Verify disk space (~10GB for all models)

## 🎓 Best Practices

1. **Start with Stella**: Best overall performance for research papers
2. **Use --delete-collection**: When changing embedding models
3. **Monitor resources**: Models require significant memory
4. **Backup collections**: Before major changes
5. **Test thoroughly**: Use small uploads first

## 🔮 Future Enhancements

- Support for additional embedding models
- Model fine-tuning capabilities
- Multi-modal embeddings (text + images)
- Distributed embedding clusters
- Model performance benchmarking