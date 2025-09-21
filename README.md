# ChromaDB Enhanced Embeddings

High-performance ChromaDB server with built-in support for multiple state-of-the-art embedding models, enabling superior semantic search for your PDF research library.

## 🚀 Quick Start

```bash
# 1. Install dependencies (includes EasyOCR)
pip install .

# 2. Verify OCR setup
python3 check_deps.py

# 3. Build the enhanced ChromaDB image (10-15 minutes)
./build.sh

# 4. Start server with Stella-400m embeddings
./server.sh -m stella

# 5. Upload PDFs with OCR support (specify your PDF directory)
./upload.sh -i /path/to/your/pdfs -e stella --delete-collection -l 10
```

## 📁 Project Structure

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-model ChromaDB Docker image |
| `build.sh` | Build script for Docker image |
| `server.sh` | Server management script |
| `upload.sh` | PDF upload script with OCR support |
| `test.sh` | Complete setup testing |
| `check_deps.py` | Dependency checker for OCR setup |
| `requirements.txt` | Python dependencies |
| `pyproject.toml` | Modern Python packaging |
| `.gitignore` | Git ignore rules |
| `LICENSE` | MIT license |

## 📋 Installation & Dependencies

### Python Dependencies
```bash
# Install all dependencies (includes Tesseract Python wrapper)
pip install .

# Check all dependencies are working
python3 check_deps.py

# Development install
pip install -e .[dev]
```

### OCR Engine Setup
Choose your preferred OCR engine:

**Option 1: Tesseract (Recommended - faster)**
```bash
# Install system dependency
# macOS: brew install tesseract
# Ubuntu/Debian: sudo apt-get install tesseract-ocr
# CentOS/RHEL: sudo yum install tesseract

# Python wrapper already installed with: pip install .
# Ready to use (default engine)
```

**Option 2: EasyOCR (Pure Python - no system deps)**
```bash
# Install EasyOCR package
pip install .[easyocr]

# Use with --ocr-engine easyocr flag
```

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
./server.sh -m modernbert -p 9001

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

### Basic Upload (OCR Enabled by Default)
```bash
# Upload with Stella embeddings and OCR
./upload.sh -i /path/to/pdfs -e stella

# Upload first 5 files only
./upload.sh -i /path/to/pdfs -e stella -l 5

# Fresh collection with ModernBERT
./upload.sh -i /path/to/pdfs -e modernbert --delete-collection
```

### OCR Options
```bash
# Tesseract is default (if system binary installed)
./upload.sh -i /path/to/pdfs -e stella

# Use EasyOCR engine (pure Python, no system deps)
./upload.sh -i /path/to/pdfs -e stella --ocr-engine easyocr

# OCR with different language (French for Tesseract)
./upload.sh -i /path/to/pdfs -e stella --ocr-language fra

# OCR with Spanish language and EasyOCR
./upload.sh -i /path/to/pdfs -e stella --ocr-engine easyocr --ocr-language es

# Disable OCR entirely (faster, but skips image PDFs)
./upload.sh -i /path/to/pdfs -e stella --disable-ocr
```

### Advanced Options
```bash
# Custom chunking parameters
./upload.sh -i /path/to/pdfs -e stella --chunk-size 2000 --chunk-overlap 400

# Remote server
./upload.sh -i /path/to/pdfs -e stella -h remote-server.com -p 9000

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

If currently using PersistentClient:
```bash
./build.sh
./server.sh -m stella
./upload.sh -i /path/to/pdfs -e stella --delete-collection
```

Then update your `claude.json` MCP configuration to use `localhost:9000`.

## 🧪 Testing

```bash
# Run comprehensive tests
./test.sh

# Test specific embedding model
./upload.sh -i /path/to/pdfs -e modernbert -l 1 -c TestCollection --delete-collection
```

## 🎛️ Environment Variables

```bash
export PDF_INPUT_PATH=/path/to/pdfs      # Required for upload.sh
export CHROMA_EMBEDDING_MODEL=stella     # Server default model
```

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
curl http://localhost:9000/api/v2/heartbeat

# Check all dependencies including OCR
python3 -c "import chromadb, fitz, easyocr, PIL; print('✅ All Dependencies OK')"

# Test OCR functionality (EasyOCR)
python3 -c "import easyocr; print('✅ EasyOCR available')"

# Test Tesseract if using it
python3 -c "import pytesseract; print('Tesseract Version:', pytesseract.get_tesseract_version())"

# Use smaller test
./upload.sh -i /path/to/pdfs -e stella -l 1 -c TestCollection --delete-collection
```

### OCR Issues
```bash
# EasyOCR issues (should work out of the box)
python3 -c "import easyocr; print('EasyOCR OK')"

# Tesseract issues (if using --ocr-engine tesseract)
tesseract --version
pip install .[tesseract]

# Test with OCR disabled if having issues
./upload.sh -i /path/to/pdfs -e stella --disable-ocr -l 1 -c TestCollection --delete-collection
```

### Model Loading Issues
- Ensure Docker has sufficient memory (8GB+ recommended)
- Check network connectivity for model downloads
- Verify disk space (~10GB for all models)

## 🎓 Best Practices

1. **Start with Stella**: Best overall performance for research papers
2. **Enable OCR**: Processes image-only PDFs automatically (enabled by default)
3. **Use --delete-collection**: When changing embedding models
4. **Monitor resources**: Models and OCR require significant memory
5. **Test OCR languages**: Use --ocr-language for non-English documents
6. **Backup collections**: Before major changes
7. **Test thoroughly**: Use small uploads first

## 🔌 Claude Code MCP Integration

### Setup Steps

1. **Start ChromaDB Server**:
   ```bash
   ./server.sh -m stella
   ```

2. **Configure MCP in claude.json**:
   ```json
   {
     "mcpServers": {
       "chroma-docker": {
         "command": "docker",
         "args": [
           "run", "-i", "--rm", "--network", "host",
           "mcp/chroma", "chroma-mcp",
           "--client-type", "http",
           "--host", "localhost",
           "--port", "9000",
           "--ssl", "false"
         ]
       }
     }
   }
   ```

3. **Test Connection**:
   ```bash
   curl http://localhost:9000/api/v2/heartbeat
   ```

4. **Restart Claude Code** to load the configuration

### Benefits
- ✅ **Superior Embeddings**: Stella-400m vs default models
- ✅ **OCR Support**: Automatically processes image-only PDFs
- ✅ **Centralized Management**: One server for all embedding needs
- ✅ **Research-Optimized**: Designed for PDF workflows

## 🔮 Future Enhancements

- Support for additional embedding models
- Model fine-tuning capabilities
- Multi-modal embeddings (text + images)
- Distributed embedding clusters
- Model performance benchmarking