# ChromaDB Enhanced Multi-Format Processing

High-performance ChromaDB server with built-in support for multiple state-of-the-art embedding models, enabling superior semantic search across PDFs, source code, and documentation with store-optimized chunking strategies.

## 🚀 Quick Start

```bash
# 1. Install dependencies (includes ASTChunk for source code)
pip install .

# 2. Verify all dependencies
python3 check_deps.py

# 3. Build the enhanced ChromaDB image (10-15 minutes)
./build.sh

# 4. Start server with Stella-400m embeddings
./server.sh -m stella

# 5. Upload content with store-specific optimization
# PDFs with OCR support
./upload.sh -i /path/to/pdfs --store pdf -e stella -c ResearchLibrary

# Source code with AST-aware chunking
./upload.sh -i /path/to/source --store source-code -e stella -c CodeLibrary

# Documentation with optimized chunking
./upload.sh -i /path/to/docs --store documentation -e stella -c DocsLibrary
```

## 📁 Project Structure

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-model ChromaDB Docker image |
| `build.sh` | Build script for Docker image |
| `server.sh` | Server management script |
| `upload.sh` | Multi-format upload script (PDF, source code, docs) |
| `embedding_functions.py` | Enhanced embedding model implementations |
| `test.sh` | Complete setup testing |
| `check_deps.py` | Dependency checker (OCR + ASTChunk) |
| `requirements.txt` | Python dependencies (includes ASTChunk) |
| `pyproject.toml` | Modern Python packaging |
| `.gitignore` | Git ignore rules |
| `LICENSE` | MIT license |

## 📋 Installation & Dependencies

### Python Dependencies
```bash
# Install all dependencies (includes ASTChunk and Tesseract wrapper)
pip install .

# Check all dependencies are working (OCR + AST parsing)
python3 check_deps.py

# Development install
pip install -e .[dev]
```

### Key Dependencies Added
- **ASTChunk** (`astchunk>=0.1.0`) - AST-aware source code chunking
- **Tree-sitter** - Multi-language parsing support (Python, Java, TypeScript, C#, etc.)
- **Enhanced metadata extraction** - Store-specific metadata for better retrieval

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

## 📄 Store Types & Chunking Strategies

The upload script supports three optimized store types, each with tailored chunking and metadata extraction:

| Store Type | Chunk Size | Overlap | Processing | Best For |
|------------|------------|---------|------------|----------|
| `pdf` | 3000 tokens | 600 tokens | OCR + Text extraction | Research papers, documents |
| `source-code` | 2000 tokens | 200 tokens | AST-aware chunking | Code analysis, API understanding |
| `documentation` | 1200 tokens | 200 tokens | Structure-aware chunking | README, wikis, tutorials |

### 🔍 PDF Store Type
- **OCR Support**: Automatic image-only PDF processing with Tesseract/EasyOCR
- **Language Support**: 100+ OCR languages supported
- **Metadata**: File size, extraction method, OCR confidence, image detection

### 💻 Source Code Store Type
- **Git Project-Aware**: Automatically detects `.git` directories and tracks project-level changes
- **Smart Change Detection**: Compares git commit hashes to detect when projects need re-indexing
- **Respects .gitignore**: Uses `git ls-files` to only index tracked files
- **AST-Aware Chunking**: Respects function/class boundaries using ASTChunk
- **Language Support**: 15+ programming languages (Python, Java, JS/TS, C#, Go, Rust, C/C++, PHP, Ruby, Kotlin, Scala, Swift)
- **Enhanced Metadata**: Programming language, function/class detection, import analysis, line counts, git project context
- **Automatic Language Detection**: Based on file extensions
- **Project Search Depth**: Control how deep to search for nested git projects

### 📚 Documentation Store Type
- **Optimized for Text**: Smaller chunks for better semantic granularity
- **Markdown Support**: Preserves structure and formatting context
- **Content Analysis**: Detects code blocks, links, and document structure
- **Metadata**: Document type, structural elements, content analysis

## 🔄 Git Project-Aware Processing

When using `--store source-code`, the system automatically detects and manages git projects with intelligent change detection:

### Key Features
- **Automatic Discovery**: Finds `.git` directories to identify project boundaries
- **Smart Change Detection**: Compares git commit hashes to detect when re-indexing is needed
- **Clean Updates**: Deletes all existing chunks for a project when its commit hash changes
- **Respects .gitignore**: Only indexes files tracked by git using `git ls-files`
- **Project Metadata**: Every chunk includes git project context (name, commit hash, remote URL, branch)

### Depth Control
```bash
--depth 1        # Only direct subdirectories (fast, good for organized workspaces)
--depth 2        # Two levels deep (includes some nested projects)
# No --depth     # Unlimited depth (finds all nested git projects)
```

### Change Detection Workflow
1. **First Run**: Indexes all git-tracked files, stores commit hash with each chunk
2. **Subsequent Runs**: Compares stored vs current commit hash
3. **If Changed**: Deletes all project chunks and re-indexes all files
4. **If Unchanged**: Uses regular file-by-file processing for new files only

### Benefits
- **Automatic Cleanup**: Moved/deleted files are automatically removed
- **Project Context**: Search results include which project and commit the code came from
- **Efficient Updates**: Only re-processes projects that have actually changed
- **Workspace Friendly**: Handles directories with multiple git projects gracefully

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

## 🚧 Known Limitations

### ChromaDB Unique Metadata Values
ChromaDB currently does not provide built-in aggregate functions or SQL-like `DISTINCT` operations for efficiently retrieving unique metadata values. This limitation affects scenarios where you need to:

- Get a list of unique project names from a large collection
- Count distinct values in metadata fields
- Perform aggregate operations on metadata

**Current Workaround:**
The most efficient approach available is to retrieve metadata-only results in small batches and manually deduplicate using Python sets:

```python
# Get all metadata without document content
all_metadatas = collection.get(include=["metadatas"])["metadatas"]

# Extract unique values using Python sets
unique_projects = {meta.get("git_project_name") for meta in all_metadatas}
unique_projects = list(unique_projects)
```

**Community Request:**
This feature has been actively requested by the ChromaDB community. You can track progress and add your support at:
- **GitHub Issue:** [Query with unique metadata filter #2873](https://github.com/chroma-core/chroma/issues/2873)

**Impact:**
For large collections (thousands of documents), retrieving unique metadata values requires scanning all documents, which is the current best practice until native aggregation support is added to ChromaDB.

## 🚨 Payload Size Error Handling

When uploading large files (especially minified JavaScript or large source files), you may encounter "413 Payload Too Large" errors. The system now provides fail-fast error handling with clear recovery options:

### Error Detection & Recovery
```bash
# If you get a payload error, the system will show:
❌ PAYLOAD TOO LARGE ERROR
📁 File: /path/to/aws-amplify.min.js
📊 File size: 1,234,567 bytes
🧩 Total chunks: 156
💾 Batch payload: ~2,500,000 characters

💡 RECOMMENDATIONS:
   Suggested chunk size: 800 tokens
   Suggested batch size: 25

🔧 RECOVERY OPTIONS:
   1. Reduce chunk size: --chunk-size 800 --batch-size 25
   2. Delete partial project: --delete-project my-project
```

### Prevention & Optimization
```bash
# Preview chunk sizes before uploading (dry-run)
./upload.sh --dry-run -i /path/to/source --store source-code

# Upload with conservative settings for large files
./upload.sh -i /path/to/source --store source-code --chunk-size 800 --batch-size 25

# Auto-cleanup failed projects
./upload.sh -i /path/to/source --store source-code --delete-failed-project
```

### Project Cleanup Commands
```bash
# Delete specific project from collection
./upload.sh --delete-project my-project-name -c MyCollection

# List available projects (shown when project not found)
./upload.sh --delete-project nonexistent -c MyCollection
```

## 📤 Multi-Format Upload Examples

### PDF Processing (Research Papers & Documents)
```bash
# Basic PDF upload with OCR (default store type)
./upload.sh -i /path/to/pdfs --store pdf -e stella -c ResearchLibrary

# OCR with EasyOCR engine (pure Python, no system deps)
./upload.sh -i /path/to/pdfs --store pdf -e stella --ocr-engine easyocr

# Multi-language OCR support
./upload.sh -i /path/to/pdfs --store pdf -e stella --ocr-language fra  # French
./upload.sh -i /path/to/pdfs --store pdf -e stella --ocr-engine easyocr --ocr-language es  # Spanish

# Disable OCR for text-only PDFs (faster processing)
./upload.sh -i /path/to/pdfs --store pdf -e stella --disable-ocr
```

### Source Code Processing (API Understanding & Analysis)
```bash
# Git project-aware source code chunking (auto-detects git projects)
./upload.sh -i /path/to/source --store source-code -e stella -c CodeLibrary

# Only scan direct subdirectories for git projects (useful for directories with many nested projects)
./upload.sh -i /workspace --store source-code -e stella -c MainProjects --depth 1

# Process specific git project (detects changes via commit hash)
./upload.sh -i ./my-project --store source-code -e stella -c MyProject --delete-collection
./upload.sh -i ./my-project --store source-code -e stella -c MyProject  # Re-run: only processes if git commit changed

# Multi-project workspace processing
./upload.sh -i /workspace --store source-code -e stella -c AllProjects  # Finds all git projects
./upload.sh -i /workspace --store source-code -e stella -c AllProjects --depth 2  # Limit search depth

# Language-specific git projects
./upload.sh -i ./python_project --store source-code -e stella -c PythonCode
./upload.sh -i ./java_project --store source-code -e stella -c JavaCode
./upload.sh -i ./typescript_project --store source-code -e stella -c TSCode

# Custom chunking for larger codebases
./upload.sh -i /path/to/source --store source-code -e stella --chunk-size 3000

# Mixed git projects and regular files (git projects get special handling)
./upload.sh -i /mixed/directory --store source-code -e stella -c MixedCode
```

### Documentation Processing (README, Wikis, Tutorials)
```bash
# Optimized documentation processing
./upload.sh -i /path/to/docs --store documentation -e stella -c DocsLibrary

# Process specific documentation types
./upload.sh -i ./wiki --store documentation -e stella -c ProjectWiki
./upload.sh -i ./tutorials --store documentation -e stella -c Tutorials

# Mixed documentation sources
./upload.sh -i ./README.md --store documentation -e stella -c ProjectDocs
./upload.sh -i ./docs --store documentation -e stella -c ProjectDocs  # Append
```

### Advanced Multi-Format Workflows
```bash
# Create specialized collections per content type
./upload.sh -i ./papers --store pdf -e stella -c Research --delete-collection
./upload.sh -i ./codebase --store source-code -e stella -c CodeAnalysis --delete-collection
./upload.sh -i ./documentation --store documentation -e stella -c ProjectDocs --delete-collection

# Git project-aware workflows
./upload.sh -i /workspace --store source-code -e stella -c WorkspaceCode --depth 1  # Top-level projects only
./upload.sh -i /workspace/thirdparty --store source-code -e stella -c ThirdPartyCode --depth 2  # Include nested libs

# Mixed source code and documentation
./upload.sh -i ./my-project --store source-code -e stella -c MyProject --delete-collection
./upload.sh -i ./my-project/docs --store documentation -e stella -c MyProjectDocs --delete-collection

# Custom chunking strategies
./upload.sh -i /path/to/files --store pdf --chunk-size 2000 --chunk-overlap 300
./upload.sh -i /path/to/source --store source-code --chunk-size 2500 --chunk-overlap 100

# Remote server deployment
./upload.sh -i /path/to/files --store pdf -h production-server.com -p 8000 -e modernbert

# Batch processing with limits
./upload.sh -i /large/dataset --store pdf -e stella -l 50 -c BatchUpload

# Incremental git project updates (only re-processes changed projects)
./upload.sh -i /workspace --store source-code -e stella -c DevEnvironment  # Daily runs
```

## 🏗️ Architecture

```
┌─────────────────┐    HTTP API    ┌──────────────────────────┐
│  Multi-Format   │───────────────▶│  Enhanced ChromaDB       │
│  Upload Client  │                │  Docker Container        │
│  ┌─────────────┐ │                │  ┌─────────────────────┐ │
│  │ PDFs + OCR  │ │                │  │ ChromaDB Server     │ │
│  │ Source Code │ │                │  │ + Stella-400m       │ │
│  │ + ASTChunk  │ │                │  │ + ModernBERT        │ │
│  │ Docs + MD   │ │                │  │ + BGE-Large         │ │
│  └─────────────┘ │                │  │ + Enhanced Metadata │ │
└─────────────────┘                │  └─────────────────────┘ │
                                   │                          │
┌─────────────────┐    HTTP API    │  Store-Specific          │
│  MCP Client     │───────────────▶│  Collections:            │
│  (Claude Code   │                │  • ResearchLibrary (PDF) │
│  semantic       │                │  • CodeLibrary (Source)  │
│  queries)       │                │  • DocsLibrary (Docs)    │
└─────────────────┘                └──────────────────────────┘
```

## 💻 Source Code Support

### Supported Programming Languages
The source code store type supports **15+ programming languages** with automatic detection:

| Language | Extensions | AST Parser | Enhanced Metadata |
|----------|------------|------------|-------------------|
| **Python** | `.py` | ✅ tree-sitter-python | Functions, classes, imports |
| **Java** | `.java` | ✅ tree-sitter-java | Methods, classes, packages |
| **JavaScript** | `.js`, `.jsx` | ✅ tree-sitter-typescript | Functions, objects, imports |
| **TypeScript** | `.ts`, `.tsx` | ✅ tree-sitter-typescript | Types, interfaces, modules |
| **C#** | `.cs` | ✅ tree-sitter-c-sharp | Methods, classes, namespaces |
| **Go** | `.go` | ✅ tree-sitter-go | Functions, structs, packages |
| **Rust** | `.rs` | ✅ tree-sitter-rust | Functions, traits, modules |
| **C/C++** | `.c`, `.cpp` | ✅ tree-sitter-cpp | Functions, classes, includes |
| **PHP** | `.php` | ✅ tree-sitter-php | Functions, classes, namespaces |
| **Ruby** | `.rb` | ✅ tree-sitter-ruby | Methods, classes, modules |
| **Kotlin** | `.kt` | ✅ (via Java parser) | Classes, functions, packages |
| **Scala** | `.scala` | ✅ (via Java parser) | Objects, classes, traits |
| **Swift** | `.swift` | ✅ (via C parser) | Functions, classes, protocols |

### AST-Aware Chunking Benefits

**Traditional Text Chunking Problems:**
```python
# ❌ Basic chunking might split mid-function
def calculate_api_response(data):
    # Processing logic here...
    return result
# CHUNK BREAK - Context lost!

class DatabaseManager:
    def connect(self):
```

**AST-Aware Chunking Solution:**
```python
# ✅ ASTChunk preserves semantic boundaries
def calculate_api_response(data):
    """Complete function with docstring intact"""
    # All related logic stays together
    return result

# New chunk starts at natural boundary
class DatabaseManager:
    """Complete class with all methods"""
    def connect(self):
        # Method implementation complete
```

### Enhanced Metadata for Code Understanding

Each source code chunk includes rich metadata for precise retrieval:

```json
{
  "store_type": "source-code",
  "programming_language": "python",
  "file_extension": ".py",
  "has_functions": true,
  "has_classes": true,
  "has_imports": true,
  "line_count": 45,
  "ast_chunked": true,
  "text_extraction_method": "astchunk_python"
}
```

### API Understanding Use Cases

**Perfect for:**
- 🔍 **API Discovery**: Find similar function signatures across projects
- 📚 **Usage Examples**: Locate how specific APIs are used in practice
- 🔧 **Implementation Patterns**: Discover common coding patterns and practices
- 🐛 **Error Handling**: Find error handling approaches for specific scenarios
- 📖 **Documentation Gap Filling**: When official docs are lacking or incomplete

**Query Examples:**
- "How to authenticate with REST APIs in Python?"
- "Show me error handling patterns for database connections"
- "Find examples of async/await usage in JavaScript"
- "What are common patterns for dependency injection in Java?"

## 📚 Documentation Processing

### Optimized for Technical Documentation

The documentation store type is specifically tuned for technical content:

**Supported Formats:**
- **Markdown** (`.md`) - README files, wikis, technical guides
- **Text** (`.txt`) - Plain text documentation
- **reStructuredText** (`.rst`) - Python documentation standard
- **AsciiDoc** (`.adoc`) - Technical documentation format
- **HTML** (`.html`) - Web documentation
- **XML** (`.xml`) - Structured documentation

### Enhanced Content Analysis

Documentation chunks include intelligent content detection:

```json
{
  "store_type": "documentation",
  "doc_type": "markdown",
  "has_code_blocks": true,
  "has_links": true,
  "line_count": 89,
  "text_extraction_method": "direct_read"
}
```

### Documentation Use Cases

**Perfect for:**
- 📖 **Project Onboarding**: Quickly understand new codebases and their documentation
- 🔗 **Cross-Reference Discovery**: Find related documentation across different projects
- 💡 **Best Practice Learning**: Extract patterns and recommendations from documentation
- 🏗️ **Architecture Understanding**: Grasp system design from architectural docs
- 🚀 **Setup Instructions**: Locate installation and configuration guides

**Query Examples:**
- "How to set up development environment for this project?"
- "What are the deployment procedures and requirements?"
- "Find architectural decisions and design patterns used"
- "Show me configuration examples and environment variables"

## 🔄 Migration from Old Setup

If currently using PersistentClient or basic PDF-only setup:
```bash
# 1. Rebuild with enhanced capabilities
./build.sh

# 2. Start server
./server.sh -m stella

# 3. Migrate existing PDFs with explicit store type
./upload.sh -i /path/to/pdfs --store pdf -e stella --delete-collection

# 4. Add new content types
./upload.sh -i /path/to/source --store source-code -e stella -c CodeLibrary
./upload.sh -i /path/to/docs --store documentation -e stella -c DocsLibrary
```

Then update your `claude.json` MCP configuration to use `localhost:9000`.

## 🧪 Testing & Validation

### Comprehensive Testing
```bash
# Run all tests (includes new store types)
./test.sh

# Test each store type individually
./upload.sh -i ./embedding_functions.py --store source-code -e stella -l 1 -c TestSource --delete-collection
./upload.sh -i ./README.md --store documentation -e stella -l 1 -c TestDocs --delete-collection
./upload.sh -i /path/to/test.pdf --store pdf -e stella -l 1 -c TestPDF --delete-collection
```

### Verify AST Chunking
```bash
# Check if ASTChunk is working properly
python3 -c "
import astchunk
from astchunk import ASTChunkBuilder
print('✅ ASTChunk available and ready')
configs = {'max_chunk_size': 1000, 'language': 'python', 'metadata_template': 'default'}
chunker = ASTChunkBuilder(**configs)
print('✅ ASTChunk chunker initialized successfully')
"
```

### Validate Store-Specific Metadata
```bash
# Query and inspect metadata for different store types
python3 -c "
import chromadb
client = chromadb.HttpClient(host='localhost', port=9000)

# Check source code metadata
try:
    collection = client.get_collection('TestSource')
    docs = collection.get(limit=1, include=['metadatas'])
    metadata = docs['metadatas'][0]
    print('Source Code Metadata:')
    print(f'  Language: {metadata.get(\"programming_language\", \"N/A\")}')
    print(f'  Has Functions: {metadata.get(\"has_functions\", \"N/A\")}')
    print(f'  AST Chunked: {metadata.get(\"ast_chunked\", \"N/A\")}')
    print('✅ Source code metadata validated')
except:
    print('⚠️  No source code collection found')

# Check documentation metadata
try:
    collection = client.get_collection('TestDocs')
    docs = collection.get(limit=1, include=['metadatas'])
    metadata = docs['metadatas'][0]
    print('Documentation Metadata:')
    print(f'  Doc Type: {metadata.get(\"doc_type\", \"N/A\")}')
    print(f'  Has Code Blocks: {metadata.get(\"has_code_blocks\", \"N/A\")}')
    print(f'  Has Links: {metadata.get(\"has_links\", \"N/A\")}')
    print('✅ Documentation metadata validated')
except:
    print('⚠️  No documentation collection found')
"
```

## 🎛️ Environment Variables

```bash
# Upload script configuration
export PDF_INPUT_PATH=/path/to/files     # Input path (works with all store types)

# Server configuration
export CHROMA_EMBEDDING_MODEL=stella     # Server default model
export TRANSFORMERS_CACHE=/models        # Model cache directory
export HF_HOME=/models                   # Hugging Face cache directory

# Store-specific defaults (optional)
export DEFAULT_STORE_TYPE=pdf            # Default store type
export DEFAULT_CHUNK_SIZE=3000           # Default chunk size (adjusted per store type)
export DEFAULT_OVERLAP=600               # Default overlap (adjusted per store type)
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

# Check all dependencies including OCR and ASTChunk
python3 -c "import chromadb, fitz, astchunk, PIL; print('✅ All Dependencies OK')"

# Test OCR functionality (EasyOCR)
python3 -c "import easyocr; print('✅ EasyOCR available')"

# Test Tesseract if using it
python3 -c "import pytesseract; print('Tesseract Version:', pytesseract.get_tesseract_version())"

# Test ASTChunk functionality
python3 -c "from astchunk import ASTChunkBuilder; print('✅ ASTChunk available')"

# Test with smaller uploads for each store type
./upload.sh -i /path/to/test.pdf --store pdf -e stella -l 1 -c TestPDF --delete-collection
./upload.sh -i ./embedding_functions.py --store source-code -e stella -l 1 -c TestCode --delete-collection
```

### OCR Issues (PDF Store Type)
```bash
# EasyOCR issues (should work out of the box)
python3 -c "import easyocr; print('EasyOCR OK')"

# Tesseract issues (if using --ocr-engine tesseract)
tesseract --version
pip install .[tesseract]

# Test with OCR disabled if having issues
./upload.sh -i /path/to/pdfs --store pdf -e stella --disable-ocr -l 1 -c TestCollection --delete-collection
```

### ASTChunk Issues (Source Code Store Type)
```bash
# Verify ASTChunk installation
python3 -c "import astchunk; from astchunk import ASTChunkBuilder; print('ASTChunk working')"

# Test with basic chunking fallback if ASTChunk fails
./upload.sh -i ./test.py --store source-code -e stella -l 1 -c TestFallback --delete-collection

# Check tree-sitter language parsers
python3 -c "
import tree_sitter_python
import tree_sitter_java
import tree_sitter_typescript
print('✅ Tree-sitter parsers available')
"

# Manual ASTChunk test
python3 -c "
from astchunk import ASTChunkBuilder
configs = {'max_chunk_size': 1000, 'language': 'python', 'metadata_template': 'default'}
chunker = ASTChunkBuilder(**configs)
result = chunker.chunkify('def hello(): print(\"Hello World\")')
print(f'✅ ASTChunk test successful: {len(result)} chunks')
"
```

### Model Loading Issues
- Ensure Docker has sufficient memory (8GB+ recommended)
- Check network connectivity for model downloads
- Verify disk space (~10GB for all models)

## 🎓 Best Practices

### Store Type Selection
1. **Choose the Right Store Type**:
   - `--store pdf` for research papers and documents
   - `--store source-code` for API understanding and code analysis
   - `--store documentation` for README files and technical guides

2. **Collection Organization**:
   - Use descriptive collection names: `ResearchLibrary`, `CodeLibrary`, `DocsLibrary`
   - Separate collections by content type for better semantic coherence
   - Consider language-specific collections for source code: `PythonCode`, `JavaCode`

### Embedding Model Strategy
3. **Model Selection by Use Case**:
   - **Stella** (recommended): Best for research papers and technical content
   - **ModernBERT**: Latest technology, good for mixed content
   - **BGE-Large**: Production-ready, reliable for all content types

### Processing Optimization
4. **Chunking Strategies**:
   - Keep default chunk sizes unless you have specific requirements
   - Source code benefits from AST-aware chunking (automatic with ASTChunk)
   - Use `--delete-collection` when changing embedding models

5. **Resource Management**:
   - Ensure Docker has 8GB+ RAM for optimal performance
   - ASTChunk requires additional memory for multiple language parsers
   - Monitor disk space for model downloads (~10GB total)

### Content-Specific Tips
6. **PDF Processing**:
   - Enable OCR by default (handles image-only PDFs)
   - Test with different OCR engines if accuracy issues occur
   - Use `--ocr-language` for non-English documents

7. **Source Code Processing**:
   - Let ASTChunk handle chunking automatically (preserves function boundaries)
   - Include test files - they often contain the best usage examples
   - Process entire project directories for complete context

8. **Documentation Processing**:
   - Include all related docs in same collection for cross-referencing
   - Markdown files provide the richest structural information
   - Smaller chunk sizes work better for precise documentation retrieval

### Quality Assurance
9. **Testing & Validation**:
   - Always test with small uploads first (`-l 5`)
   - Verify metadata is populated correctly for each store type
   - Use `python3 check_deps.py` to validate all dependencies

10. **Backup & Recovery**:
    - Backup collections before major changes
    - Keep source files organized for re-processing if needed
    - Document your embedding model choices for consistency

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
- ✅ **Superior Embeddings**: Stella-400m, ModernBERT, BGE-Large vs default models
- ✅ **Multi-Format Support**: PDFs, source code, and documentation in one system
- ✅ **AST-Aware Code Analysis**: Semantic chunking preserves function boundaries
- ✅ **Enhanced Metadata**: Store-specific metadata for precise retrieval
- ✅ **OCR Support**: Automatically processes image-only PDFs
- ✅ **API Understanding**: Perfect for analyzing underdocumented codebases
- ✅ **Centralized Management**: One server for all content types
- ✅ **Research & Development Optimized**: Designed for technical workflows

## 🔮 Future Enhancements

- Support for additional embedding models
- Model fine-tuning capabilities
- Multi-modal embeddings (text + images)
- Distributed embedding clusters
- Model performance benchmarking