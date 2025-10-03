#!/usr/bin/env bash

# Script to upload files to ChromaDB with store-specific optimizations
# Supports PDFs (with OCR), source code (with AST chunking), and markdown
# Works with both persistence (local) and remote ChromaDB clients
# 
# Usage: ./upload_new_pdfs.sh [OPTIONS]
#
# Options:
#   -c, --collection NAME      ChromaDB collection name (default: ResearchLibrary)
#   -h, --host HOST            ChromaDB host for remote client (default: localhost)
#   -p, --port PORT            ChromaDB port for remote client (default: 9000)
#   -l, --limit NUMBER         Maximum number of files to upload (optional)
#   -i, --input-path PATH      Path to recursively search for files (required)"
#   -d, --data-path PATH       Path for ChromaDB persistence data storage (forces persistence mode)
#   -e, --embedding-model MODEL Embedding model (stella|modernbert|bge-large|default) [default: stella]
#   --store TYPE               Store type: pdf, source-code, markdown [default: pdf]
#   --chunk-size TOKENS        Chunk size in tokens (auto=model-specific, or custom number)
#   --chunk-overlap TOKENS     Chunk overlap in tokens (auto=model-specific, or custom number)
#   --batch-size NUMBER        Upload batch size to avoid payload limits (default: 50)
#   --delete-collection        Delete and recreate the collection before upload
#   --delete-project NAME      Delete specific git project from collection
#   --delete-failed-project    Auto-delete project if any upload fails
#   --dry-run                  Preview chunk sizes without uploading
#   --disable-ocr              Disable OCR for image PDFs (OCR enabled by default)
#   --ocr-engine ENGINE        OCR engine: tesseract, easyocr (default: tesseract)
#   --ocr-language LANG        OCR language code (default: eng)
#   --help                     Show this help message
#
# Path Types:
#   --input-path: Directory containing files to index (searched recursively by store type)
#   --data-path:  Directory where ChromaDB stores its database files (persistence mode only)
#
# Client Selection:
#   - If --data-path is specified: uses PersistentClient
#   - Otherwise: uses HttpClient with --host and --port (default: localhost:9000)
#
# Environment variables:
#   PDF_INPUT_PATH: Path to directory containing files (alternative to -i option)
#   CHROMA_DATA_PATH: Default path for persistence client data directory

set -e

# Default values
COLLECTION_NAME="ResearchLibrary"
CHROMA_HOST="localhost"
CHROMA_PORT="9000"
UPLOAD_LIMIT=""
INPUT_PATH="${PDF_INPUT_PATH:-}"  # Use environment variable or require CLI option
CHROMA_DATA_DIR=""
CLIENT_TYPE="remote"
EMBEDDING_MODEL="stella"
CHUNK_SIZE="auto"
CHUNK_OVERLAP="auto"
BATCH_SIZE="50"
DELETE_COLLECTION="false"
DELETE_PROJECT=""
DELETE_FAILED_PROJECT="false"
DRY_RUN="false"
OCR_ENABLED="true"
OCR_ENGINE="tesseract"
OCR_LANGUAGE="eng"
STORE_TYPE="pdf"
GIT_DEPTH=""

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --collection NAME      ChromaDB collection name (default: ResearchLibrary)"
    echo "  -h, --host HOST            ChromaDB host for remote client (default: localhost)"
    echo "  -p, --port PORT            ChromaDB port for remote client (default: 9000)"
    echo "  -l, --limit NUMBER         Maximum number of files to upload (optional)"
    echo "  -i, --input-path PATH      Path to recursively search for PDF files (required)"
    echo "  -d, --data-path PATH       Path for ChromaDB persistence data storage (forces persistence mode)"
    echo "  -e, --embedding-model MODEL Embedding model: stella, modernbert, bge-large, default [default: stella]"
    echo "  --store TYPE               Store type: pdf, source-code, markdown [default: pdf]"
    echo "  --chunk-size TOKENS        Chunk size in tokens (auto=model-optimized, or specify number)"
    echo "  --chunk-overlap TOKENS     Chunk overlap in tokens (auto=model-optimized, or specify number)"
    echo "  --batch-size NUMBER        Upload batch size to avoid payload limits (default: 50)"
    echo "  --depth LEVELS             Git project search depth (1=direct subdirs only, default: unlimited)"
    echo "  --delete-collection        Delete and recreate the collection before upload"
    echo "  --delete-project NAME      Delete specific git project from collection"
    echo "  --delete-failed-project    Auto-delete project if any upload fails"
    echo "  --dry-run                  Preview chunk sizes without uploading"
    echo "  --disable-ocr              Disable OCR for image PDFs (OCR enabled by default)"
    echo "  --ocr-engine ENGINE        OCR engine: tesseract, easyocr (default: tesseract)"
    echo "  --ocr-language LANG        OCR language code (default: eng)"
    echo "  --help                     Show this help message"
    echo ""
    echo "Path Types:"
    echo "  --input-path: Directory containing PDF files to index (searched recursively)"
    echo "  --data-path:  Directory where ChromaDB stores its database files (persistence mode only)"
    echo ""
    echo "Client Selection:"
    echo "  - If --data-path is specified: uses PersistentClient"
    echo "  - Otherwise: uses HttpClient with --host and --port (default: localhost:9000)"
    echo ""
    echo "Environment variables:"
    echo "  PDF_INPUT_PATH: Path to directory containing PDF files (alternative to -i option)"
    echo "  CHROMA_DATA_PATH: Default path for persistence client data directory"
    echo ""
    echo "Embedding Models:"
    echo "  stella      - Stella-400m (Top MTEB performer, 1024 dims)"
    echo "  modernbert  - ModernBERT-large (Latest state-of-the-art, 1024 dims)"
    echo "  bge-large   - BGE-Large (Production proven, 1024 dims)"
    echo "  default     - SentenceTransformers default (all-MiniLM-L6-v2, 384 dims)"
    echo ""
    echo "Examples:"
    echo "  # Upload PDFs (default)"
    echo "  $0 -i /path/to/pdfs -c MyCollection -e stella"
    echo ""
    echo "  # Upload source code with AST-aware chunking"
    echo "  $0 -i /path/to/source --store source-code -c CodeLibrary -e stella"
    echo ""
    echo "  # Upload markdown documentation files"
    echo "  $0 -i /path/to/docs --store markdown -c DocsLibrary -e stella"
    echo ""
    echo "  # Advanced options - custom chunk size"
    echo "  $0 -i /path/to/files --store pdf --delete-collection -c MyCollection -e stella --chunk-size 400"
    echo ""
    echo "  # Model-optimized chunking (recommended)"
    echo "  $0 -i /path/to/files --store pdf -c MyCollection -e stella  # Uses optimal 460 tokens for Stella"
    echo ""
    echo "  # Handling large files (if you get payload size errors)"
    echo "  $0 -i /path/to/source --store source-code --batch-size 25 --chunk-size 1000"
    echo ""
    echo "  # Project cleanup and recovery"
    echo "  $0 --delete-project my-project-name  # Delete specific project"
    echo "  $0 -i /path/to/source --store source-code --delete-failed-project  # Auto-cleanup on failure"
    echo ""
    echo "  # Preview and optimize settings"
    echo "  $0 -i /path/to/source --store source-code --dry-run  # Preview chunk sizes"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--collection)
            COLLECTION_NAME="$2"
            shift 2
            ;;
        -h|--host)
            CHROMA_HOST="$2"
            shift 2
            ;;
        -p|--port)
            CHROMA_PORT="$2"
            shift 2
            ;;
        -l|--limit)
            UPLOAD_LIMIT="$2"
            shift 2
            ;;
        -i|--input-path)
            INPUT_PATH="$2"
            shift 2
            ;;
        -d|--data-path)
            CHROMA_DATA_DIR="$2"
            CLIENT_TYPE="persistence"
            shift 2
            ;;
        -e|--embedding-model)
            EMBEDDING_MODEL="$2"
            shift 2
            ;;
        --store)
            STORE_TYPE="$2"
            shift 2
            ;;
        --chunk-size)
            CHUNK_SIZE="$2"
            shift 2
            ;;
        --chunk-overlap)
            CHUNK_OVERLAP="$2"
            shift 2
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --delete-collection)
            DELETE_COLLECTION="true"
            shift
            ;;
        --delete-project)
            DELETE_PROJECT="$2"
            shift 2
            ;;
        --delete-failed-project)
            DELETE_FAILED_PROJECT="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --disable-ocr)
            OCR_ENABLED="false"
            shift
            ;;
        --ocr-engine)
            OCR_ENGINE="$2"
            shift 2
            ;;
        --ocr-language)
            OCR_LANGUAGE="$2"
            shift 2
            ;;
        --depth)
            GIT_DEPTH="$2"
            shift 2
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

# Set default data directory if using persistence mode but no path specified
if [ "$CLIENT_TYPE" = "persistence" ] && [ -z "$CHROMA_DATA_DIR" ]; then
    CHROMA_DATA_DIR="${CHROMA_DATA_PATH:-./chroma_data_${COLLECTION_NAME}}"
fi

# Validate embedding model
case "$EMBEDDING_MODEL" in
    stella|modernbert|bge-large|default)
        ;;
    *)
        echo "❌ Invalid embedding model: $EMBEDDING_MODEL"
        echo "Valid options: stella, modernbert, bge-large, default"
        echo "Use --help for more information"
        exit 1
        ;;
esac

# Validate OCR engine
case "$OCR_ENGINE" in
    tesseract|easyocr)
        ;;
    *)
        echo "❌ Invalid OCR engine: $OCR_ENGINE"
        echo "Valid options: tesseract, easyocr"
        echo "Use --help for more information"
        exit 1
        ;;
esac

# Validate depth parameter
if [ -n "$GIT_DEPTH" ]; then
    # Check if depth is a positive integer
    if ! [[ "$GIT_DEPTH" =~ ^[0-9]+$ ]] || [ "$GIT_DEPTH" -lt 1 ]; then
        echo "❌ Invalid depth value: $GIT_DEPTH"
        echo "Depth must be a positive integer (1 or higher)"
        echo "Use --help for more information"
        exit 1
    fi
fi

# Set model-specific defaults with 10% safety margin for query context
set_model_defaults() {
    local model="$1"
    local store="$2"

    case "$model" in
        stella)
            # Stella: 512 token limit, 10% safety margin = 460 tokens
            MODEL_CHUNK_SIZE="460"
            MODEL_CHUNK_OVERLAP="46"  # 10% overlap
            ;;
        modernbert)
            # ModernBERT: 8192 token limit, use conservative 1024 with 10% margin = 920 tokens
            MODEL_CHUNK_SIZE="920"
            MODEL_CHUNK_OVERLAP="92"  # 10% overlap
            ;;
        bge-large)
            # BGE-Large: ~512 token limit (BERT-based), 10% safety margin = 460 tokens
            MODEL_CHUNK_SIZE="460"
            MODEL_CHUNK_OVERLAP="46"  # 10% overlap
            ;;
        default)
            # Default SentenceTransformers: all-MiniLM-L6-v2, ~512 tokens
            MODEL_CHUNK_SIZE="460"
            MODEL_CHUNK_OVERLAP="46"  # 10% overlap
            ;;
        *)
            echo "❌ Unknown model for chunk size calculation: $model"
            exit 1
            ;;
    esac

    # Apply store-specific adjustments if needed
    case "$store" in
        source-code)
            # Source code benefits from slightly smaller chunks for better AST parsing
            MODEL_CHUNK_SIZE="$((MODEL_CHUNK_SIZE - 60))"
            MODEL_CHUNK_OVERLAP="$((MODEL_CHUNK_OVERLAP / 2))"
            ;;
        markdown)
            # Markdown can use slightly smaller chunks for better semantic coherence
            # Extra reduction for heading context preservation
            MODEL_CHUNK_SIZE="$((MODEL_CHUNK_SIZE - 30))"
            ;;
        pdf)
            # PDFs use default model settings
            ;;
    esac
}

# Set chunk sizes based on embedding model if auto
if [ "$CHUNK_SIZE" = "auto" ]; then
    set_model_defaults "$EMBEDDING_MODEL" "$STORE_TYPE"
    CHUNK_SIZE="$MODEL_CHUNK_SIZE"
    CHUNK_OVERLAP="$MODEL_CHUNK_OVERLAP"
fi

# Validate store type and apply other defaults
case "$STORE_TYPE" in
    pdf)
        # PDF settings
        ;;
    source-code)
        # Disable OCR for source code by default
        if [ "$OCR_ENABLED" = "true" ]; then
            OCR_ENABLED="false"
        fi
        ;;
    markdown)
        # Disable OCR for markdown by default
        if [ "$OCR_ENABLED" = "true" ]; then
            OCR_ENABLED="false"
        fi
        ;;
    *)
        echo "❌ Invalid store type: $STORE_TYPE"
        echo "Valid options: pdf, source-code, markdown"
        echo "Use --help for more information"
        exit 1
        ;;
esac

# Validate chunk sizes are reasonable
if [ "$CHUNK_SIZE" -gt 1000 ]; then
    echo "⚠️  Warning: Chunk size $CHUNK_SIZE tokens is quite large"
    echo "   This may exceed optimal embedding model limits"
    echo "   Consider using model-specific defaults with --chunk-size auto"
fi

# Function to get file extensions based on store type
get_file_extensions() {
    case "$STORE_TYPE" in
        pdf)
            echo "*.pdf"
            ;;
        source-code)
            echo "*.py *.java *.js *.ts *.tsx *.jsx *.go *.rs *.cpp *.c *.cs *.php *.rb *.kt *.scala *.swift"
            ;;
        markdown)
            echo "*.md *.txt *.rst *.adoc *.html *.xml"
            ;;
    esac
}

# Function to find git project roots in a directory
find_git_projects() {
    local input_path="$1"
    local output_file="$2"
    local depth="$3"  # Optional depth parameter

    # Clear output file
    > "$output_file"

    # Build find command with optional maxdepth
    local find_cmd="find \"$input_path\""

    if [ -n "$depth" ]; then
        # For depth=1, we want maxdepth=2 (input_path + 1 level down for .git directories)
        local max_depth=$((depth + 1))
        find_cmd="$find_cmd -maxdepth $max_depth"
    fi

    find_cmd="$find_cmd -name \".git\" -type d"

    # Execute the find command and process results
    eval "$find_cmd" | while read -r git_dir; do
        project_root=$(dirname "$git_dir")
        echo "$project_root" >> "$output_file"
    done

    # Remove duplicates and sort
    if [ -f "$output_file" ]; then
        sort -u "$output_file" -o "$output_file"
    fi
}

# Function to get git metadata for a project
get_git_metadata() {
    local project_root="$1"
    local metadata_file="$2"

    if [ ! -d "$project_root/.git" ]; then
        echo "ERROR: Not a git repository: $project_root" >&2
        return 1
    fi

    cd "$project_root" || return 1

    # Get git metadata
    local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local remote_url=$(git remote get-url origin 2>/dev/null || echo "unknown")
    local branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    local project_name=$(basename "$project_root")

    # Write metadata to file
    cat > "$metadata_file" << EOF
GIT_PROJECT_ROOT="$project_root"
GIT_COMMIT_HASH="$commit_hash"
GIT_REMOTE_URL="$remote_url"
GIT_BRANCH="$branch"
GIT_PROJECT_NAME="$project_name"
EOF

    cd - > /dev/null
    return 0
}

# Function to find files based on store type
find_files() {
    local input_path="$1"
    local output_file="$2"
    local extensions=$(get_file_extensions)

    # Clear output file
    > "$output_file"

    if [ "$STORE_TYPE" = "source-code" ]; then
        # For source code, use git-aware file discovery
        local git_projects_file="/tmp/git_projects_$$.txt"
        find_git_projects "$input_path" "$git_projects_file" "$GIT_DEPTH"

        if [ -s "$git_projects_file" ]; then
            # Process each git project
            while IFS= read -r project_root; do
                echo "  Found git project: $project_root"

                # Get files from git ls-files (respects .gitignore)
                cd "$project_root" || continue

                # Use git ls-files and filter by extensions
                for ext in $extensions; do
                    # Convert shell glob to git pathspec pattern
                    git_pattern=$(echo "$ext" | sed 's/\*//')  # Remove leading *
                    git ls-files "*$git_pattern" 2>/dev/null >> "$output_file" || true
                done

                cd - > /dev/null
            done < "$git_projects_file"

            # Convert relative paths to absolute paths
            local temp_file="/tmp/absolute_paths_$$.txt"
            > "$temp_file"

            while IFS= read -r relative_path; do
                # Find which project this file belongs to
                while IFS= read -r project_root; do
                    if [ -f "$project_root/$relative_path" ]; then
                        echo "$project_root/$relative_path" >> "$temp_file"
                        break
                    fi
                done < "$git_projects_file"
            done < "$output_file"

            mv "$temp_file" "$output_file"
        else
            echo "  No git projects found, falling back to regular file search"
            # Fall back to regular find for non-git directories
            for ext in $extensions; do
                find "$input_path" -name "$ext" -type f >> "$output_file" 2>/dev/null || true
            done
        fi

        rm -f "$git_projects_file"
    else
        # For PDF and markdown, use regular find
        # Use proper quoting to prevent glob expansion
        while IFS= read -r ext; do
            find "$input_path" -name "$ext" -type f >> "$output_file" 2>/dev/null || true
        done < <(echo "$extensions" | tr ' ' '\n')
    fi
}

# Validate that input path is provided (unless doing project deletion only)
if [ -z "$INPUT_PATH" ] && [ -z "$DELETE_PROJECT" ]; then
    echo "❌ Error: Input path is required"
    echo ""
    echo "Please specify the PDF input path using one of these methods:"
    echo "  1. CLI option: $0 -i /path/to/pdfs"
    echo "  2. Environment variable: PDF_INPUT_PATH=/path/to/pdfs $0"
    echo ""
    echo "Use --help for more information"
    exit 1
fi

LOG_FILE="/tmp/upload_new_log_$(date +%Y%m%d_%H%M%S).txt"
MAX_PARALLEL_JOBS=$(sysctl -n hw.ncpu)  # Use number of CPU cores

# Validate input path exists (unless doing project deletion only)
if [ -n "$INPUT_PATH" ] && [ ! -d "$INPUT_PATH" ]; then
    echo "❌ Input path does not exist: $INPUT_PATH"
    exit 1
fi

# Skip main intro for project deletion mode
if [ -z "$DELETE_PROJECT" ]; then
    echo "Starting SMART PDF upload to ChromaDB with Enhanced Embeddings"
    echo "Collection: $COLLECTION_NAME"
    echo "Input path: $INPUT_PATH"
else
    echo "ChromaDB Project Management"
    echo "Collection: $COLLECTION_NAME"
fi
echo "Client type: $CLIENT_TYPE"
if [ "$CLIENT_TYPE" = "remote" ]; then
    echo "ChromaDB: $CHROMA_HOST:$CHROMA_PORT"
else
    echo "Data directory: $CHROMA_DATA_DIR"
fi
echo "Embedding model: $EMBEDDING_MODEL"
case "$EMBEDDING_MODEL" in
    stella)
        echo "  → Stella-400m (1024 dims, Top MTEB performer)"
        ;;
    modernbert)
        echo "  → ModernBERT-large (1024 dims, Latest state-of-the-art)"
        ;;
    bge-large)
        echo "  → BGE-Large (1024 dims, Production proven)"
        ;;
    default)
        echo "  → SentenceTransformers default (384 dims, all-MiniLM-L6-v2)"
        ;;
esac
echo "Chunk size: $CHUNK_SIZE tokens (model-optimized for $EMBEDDING_MODEL)"
echo "Chunk overlap: $CHUNK_OVERLAP tokens"
if [ "$STORE_TYPE" = "source-code" ]; then
    if [ -n "$GIT_DEPTH" ]; then
        echo "Git project search depth: $GIT_DEPTH levels"
    else
        echo "Git project search depth: unlimited"
    fi
fi
echo "OCR enabled: $OCR_ENABLED"
if [ "$OCR_ENABLED" = "true" ]; then
    echo "  → OCR engine: $OCR_ENGINE"
    echo "  → OCR language: $OCR_LANGUAGE"
fi
if [ "$DELETE_COLLECTION" = "true" ]; then
    echo "⚠ Collection will be deleted and recreated"
fi
echo "Parallel jobs: $MAX_PARALLEL_JOBS (CPU cores)"
if [ -n "$UPLOAD_LIMIT" ]; then
    echo "Upload limit: $UPLOAD_LIMIT files"
fi
echo "Log file: $LOG_FILE"

# Check if required Python packages are available (simplified for server-side embeddings)
echo "Checking Python dependencies..."
python3 -c "
try:
    import chromadb
    import fitz  # pymupdf
    import PIL  # Pillow
    import packaging.version
    print('✓ Core packages available')
    print(f'  chromadb version: {chromadb.__version__}')
    print(f'  pymupdf version: {fitz.version[0]}')
    print(f'  pillow version: {PIL.__version__}')

    # Verify ChromaDB version compatibility
    min_version = '1.0.0'
    if packaging.version.parse(chromadb.__version__) < packaging.version.parse(min_version):
        print(f'⚠ Warning: ChromaDB version {chromadb.__version__} may not be compatible')
        print(f'  Recommended: pip install --upgrade chromadb')
    else:
        print(f'✓ ChromaDB version {chromadb.__version__} is compatible')

    # Check OCR dependencies if enabled
    ocr_enabled = '$OCR_ENABLED' == 'true'
    ocr_engine = '$OCR_ENGINE'

    if ocr_enabled:
        ocr_available = False
        if ocr_engine == 'tesseract':
            try:
                import pytesseract
                # Test tesseract binary
                version = pytesseract.get_tesseract_version()
                print(f'✓ Tesseract OCR available (version: {version})')
                ocr_available = True
            except Exception as e:
                print(f'❌ Tesseract OCR not available: {e}')
                print('  System dependency required. Install with:')
                print('    macOS: brew install tesseract')
                print('    Ubuntu/Debian: sudo apt-get install tesseract-ocr')
                print('    CentOS/RHEL: sudo yum install tesseract')
                print('  Or use EasyOCR (no system deps): pip install .[easyocr] --ocr-engine easyocr')
                print('  Or disable OCR with: --disable-ocr')
        elif ocr_engine == 'easyocr':
            try:
                import easyocr
                print('✓ EasyOCR available (pure Python, no system dependencies)')
                ocr_available = True
            except ImportError:
                print('❌ EasyOCR not available')
                print('  Install with: pip install .[easyocr]')
                print('  Or use tesseract: --ocr-engine tesseract')
                print('  Or disable OCR with: --disable-ocr')

        if not ocr_available:
            print('❌ OCR dependencies not met - exiting')
            print('  Fix dependencies or use --disable-ocr flag')
            exit(1)
        else:
            print(f'ℹ️ OCR enabled with {ocr_engine} engine')
    else:
        print('ℹ️ OCR disabled - image PDFs will be skipped')

    # Note about server-side embeddings
    print('ℹ️ Using server-side embeddings - no local ML models required')

except ImportError as e:
    print(f'✗ Missing package: {e}')
    print('Install dependencies with: pip install .')
    exit(1)
" 2>&1 | tee -a "$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "Please install required packages: pip install ."
    exit 1
fi

# Test ChromaDB connection
echo ""
echo "Testing ChromaDB connection..."
if [ "$CLIENT_TYPE" = "remote" ]; then
    if ! curl -s "$CHROMA_HOST:$CHROMA_PORT/api/v2/heartbeat" > /dev/null 2>&1; then
        echo "❌ Cannot connect to ChromaDB at $CHROMA_HOST:$CHROMA_PORT"
        if [ "$CHROMA_HOST" = "localhost" ]; then
            echo "💡 Run: ./setup_local_chroma.sh $COLLECTION_NAME"
        fi
        exit 1
    fi
    echo "✅ ChromaDB is running"
else
    echo "✅ Using persistence client (data path: $CHROMA_DATA_DIR)"
    # Create data directory if it doesn't exist
    mkdir -p "$CHROMA_DATA_DIR"
fi

# Handle project deletion if requested
if [ -n "$DELETE_PROJECT" ]; then
    echo ""
    echo "🗑️ Deleting project '$DELETE_PROJECT' from collection '$COLLECTION_NAME'..."

    python3 -c "
import chromadb
import sys

try:
    if '$CLIENT_TYPE' == 'remote':
        client = chromadb.HttpClient(host='$CHROMA_HOST', port=$CHROMA_PORT)
    else:
        client = chromadb.PersistentClient(path='$CHROMA_DATA_DIR')

    try:
        collection = client.get_collection('$COLLECTION_NAME')
        print(f'Found collection: {collection.name}')

        # Query for documents from this project (try by project name first)
        existing_docs = collection.get(
            where={'git_project_name': '$DELETE_PROJECT'},
            include=['metadatas'],
            limit=10  # Just need to check if project exists
        )

        # If not found by name, try by project root path containing the name
        if not existing_docs['ids']:
            all_docs = collection.get(include=['metadatas'], limit=1000)
            matching_ids = []
            for i, metadata in enumerate(all_docs['metadatas']):
                if metadata and 'git_project_root' in metadata:
                    if '$DELETE_PROJECT' in metadata['git_project_root']:
                        matching_ids.append(all_docs['ids'][i])

            if matching_ids:
                existing_docs = {'ids': matching_ids[:10], 'metadatas': [all_docs['metadatas'][all_docs['ids'].index(id)] for id in matching_ids[:10]]}

        if not existing_docs['ids']:
            print(f'⚠️  Project \"$DELETE_PROJECT\" not found in collection')
            print('Available projects:')

            # Get sample of all projects
            all_docs = collection.get(include=['metadatas'], limit=100)
            projects = set()
            for metadata in all_docs['metadatas']:
                if metadata and 'git_project_name' in metadata:
                    projects.add(metadata['git_project_name'])

            if projects:
                for project in sorted(projects):
                    print(f'  - {project}')
            else:
                print('  (No git projects found)')

            sys.exit(1)

        print(f'Found project \"$DELETE_PROJECT\" - deleting all chunks...')

        # Get all document IDs for this project in batches
        all_project_ids = []
        batch_size = 1000
        offset = 0

        while True:
            # Get documents by project name
            batch = collection.get(
                where={'git_project_name': '$DELETE_PROJECT'},
                include=['metadatas'],
                limit=batch_size,
                offset=offset
            )

            # If no more by name, try by project root path
            if not batch['ids'] and offset == 0:
                all_docs = collection.get(include=['metadatas'], limit=10000)
                matching_ids = []
                for i, metadata in enumerate(all_docs['metadatas']):
                    if metadata and 'git_project_root' in metadata:
                        if '$DELETE_PROJECT' in metadata['git_project_root']:
                            matching_ids.append(all_docs['ids'][i])

                # Create batch structure from matching IDs
                if matching_ids:
                    batch_ids = matching_ids[offset:offset+batch_size]
                    batch = {'ids': batch_ids, 'metadatas': [all_docs['metadatas'][all_docs['ids'].index(id)] for id in batch_ids]}

            if not batch['ids']:
                break

            all_project_ids.extend(batch['ids'])
            offset += batch_size

            if len(batch['ids']) < batch_size:
                break

        if all_project_ids:
            # Delete in batches (ChromaDB delete has limits)
            delete_batch_size = 100
            deleted_count = 0

            for i in range(0, len(all_project_ids), delete_batch_size):
                batch_ids = all_project_ids[i:i+delete_batch_size]
                collection.delete(ids=batch_ids)
                deleted_count += len(batch_ids)

            print(f'✅ Deleted {deleted_count} chunks from project \"$DELETE_PROJECT\"')
        else:
            print('⚠️  No chunks found to delete')

    except Exception as e:
        if 'does not exist' in str(e):
            print(f'❌ Collection \"$COLLECTION_NAME\" does not exist')
        else:
            print(f'❌ Error accessing collection: {e}')
        sys.exit(1)

except Exception as e:
    print(f'❌ Error connecting to ChromaDB: {e}')
    sys.exit(1)
" 2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        echo "✅ Project deletion completed successfully"
        echo "You can now re-run the upload command to re-index the project"
        exit 0
    else
        echo "❌ Project deletion failed"
        exit 1
    fi
fi

# Handle collection deletion if requested
if [ "$DELETE_COLLECTION" = "true" ]; then
    echo ""
    echo "🗑️ Deleting existing collection '$COLLECTION_NAME'..."
    python3 -c "
import chromadb
import sys

try:
    if '$CLIENT_TYPE' == 'remote':
        client = chromadb.HttpClient(host='$CHROMA_HOST', port=$CHROMA_PORT)
    else:
        client = chromadb.PersistentClient(path='$CHROMA_DATA_DIR')

    try:
        client.delete_collection('$COLLECTION_NAME')
        print('✅ Collection \"$COLLECTION_NAME\" deleted successfully')
    except Exception as e:
        if 'does not exist' in str(e).lower():
            print('ℹ️ Collection \"$COLLECTION_NAME\" did not exist')
        else:
            print(f'⚠️ Error deleting collection: {e}')

    # Create new empty collection with specified embedding model
    try:
        # For server-side embeddings, we don't specify embedding function here
        # The server will handle embedding based on its configuration
        collection = client.create_collection('$COLLECTION_NAME')
        print(f'✅ Created new empty collection: {collection.name}')
        print(f'Server will use embedding model: $EMBEDDING_MODEL')
    except Exception as e:
        print(f'❌ Error creating collection: {e}')
        sys.exit(1)

except Exception as e:
    print(f'❌ Error connecting to ChromaDB: {e}')
    sys.exit(1)
" 2>&1 | tee -a "$LOG_FILE"

    if [ $? -ne 0 ]; then
        echo "❌ Failed to delete/recreate collection"
        exit 1
    fi
fi

# Handle git project change detection for source-code
if [ "$STORE_TYPE" = "source-code" ]; then
    echo ""
    echo "Checking for git project changes..."

    # Find git projects in input path
    GIT_PROJECTS_FILE="/tmp/git_projects_${COLLECTION_NAME}_$(date +%s).txt"
    find_git_projects "$INPUT_PATH" "$GIT_PROJECTS_FILE" "$GIT_DEPTH"

    if [ -s "$GIT_PROJECTS_FILE" ]; then
        # Check each git project for changes
        while IFS= read -r project_root; do
            project_name=$(basename "$project_root")
            echo "Checking git project: $project_name"

            # Get current git metadata
            GIT_METADATA_FILE="/tmp/git_metadata_${project_name}_$(date +%s).txt"
            if get_git_metadata "$project_root" "$GIT_METADATA_FILE"; then
                source "$GIT_METADATA_FILE"

                # Check if project exists in ChromaDB and compare commit hash
                python3 -c "
import chromadb
import sys

try:
    if '$CLIENT_TYPE' == 'remote':
        client = chromadb.HttpClient(host='$CHROMA_HOST', port=$CHROMA_PORT)
    else:
        client = chromadb.PersistentClient(path='$CHROMA_DATA_DIR')

    try:
        collection = client.get_collection('$COLLECTION_NAME')

        # Query for documents from this project
        existing_docs = collection.get(
            where={'git_project_root': '$GIT_PROJECT_ROOT'},
            include=['metadatas'],
            limit=10  # Just need to check a few to get the commit hash
        )

        if existing_docs['ids']:
            stored_commit = existing_docs['metadatas'][0].get('git_commit_hash', 'unknown')
            current_commit = '$GIT_COMMIT_HASH'

            print(f'  Stored commit:  {stored_commit[:12] if stored_commit != \"unknown\" else \"unknown\"}')
            print(f'  Current commit: {current_commit[:12]}')

            if stored_commit != current_commit:
                print('  🔄 Project has changed, deleting existing chunks...')

                # Delete all chunks for this project
                # Get all document IDs for this project in batches
                all_project_ids = []
                batch_size = 1000
                offset = 0

                while True:
                    batch = collection.get(
                        where={'git_project_root': '$GIT_PROJECT_ROOT'},
                        include=['metadatas'],
                        limit=batch_size,
                        offset=offset
                    )

                    if not batch['ids']:
                        break

                    all_project_ids.extend(batch['ids'])
                    offset += batch_size

                    if len(batch['ids']) < batch_size:
                        break

                if all_project_ids:
                    # Delete in batches (ChromaDB delete has limits)
                    delete_batch_size = 100
                    deleted_count = 0

                    for i in range(0, len(all_project_ids), delete_batch_size):
                        batch_ids = all_project_ids[i:i+delete_batch_size]
                        collection.delete(ids=batch_ids)
                        deleted_count += len(batch_ids)

                    print(f'  ✅ Deleted {deleted_count} existing chunks')
                    sys.exit(10)  # Signal that project was deleted
                else:
                    print('  ⚠️ No chunks found to delete')
                    sys.exit(11)  # Signal no chunks to delete
            else:
                print('  ✓ Project unchanged, will check individual files')
                sys.exit(0)  # Normal processing
        else:
            print('  📥 New project, will index all files')
            sys.exit(0)  # Normal processing

    except Exception as e:
        if 'does not exist' in str(e):
            print('  📥 Collection does not exist, will create and index all files')
            sys.exit(0)
        else:
            print(f'Error querying collection: {e}')
            sys.exit(1)

except Exception as e:
    print(f'Error connecting to ChromaDB: {e}')
    sys.exit(1)
"
                check_result=$?

                if [ $check_result -eq 10 ]; then
                    echo "  Project $project_name was updated and old chunks deleted"
                elif [ $check_result -eq 11 ]; then
                    echo "  Project $project_name had no existing chunks"
                elif [ $check_result -eq 0 ]; then
                    echo "  Project $project_name processing normally"
                else
                    echo "  Error checking project $project_name"
                fi

                rm -f "$GIT_METADATA_FILE"
            else
                echo "  ⚠️ Could not get git metadata for $project_root"
            fi
        done < "$GIT_PROJECTS_FILE"

        rm -f "$GIT_PROJECTS_FILE"
    else
        echo "No git projects found in input path"
    fi
fi

# Query ChromaDB for existing files
echo ""
echo "Querying ChromaDB for existing files..."
EXISTING_FILES_LIST="/tmp/existing_files_${COLLECTION_NAME}_$(date +%s).txt"

python3 -c "
import chromadb
import sys

try:
    # Use appropriate client based on CLIENT_TYPE
    if '$CLIENT_TYPE' == 'remote':
        client = chromadb.HttpClient(host='$CHROMA_HOST', port=$CHROMA_PORT)
        print('✓ Connected to ChromaDB using HttpClient')
    else:
        client = chromadb.PersistentClient(path='$CHROMA_DATA_DIR')
        print('✓ Connected to ChromaDB using PersistentClient')

    # Set embedding model info for server communication
    embedding_model = '$EMBEDDING_MODEL'
    print(f'Using embedding model: {embedding_model}')
    
    try:
        collection = client.get_collection('$COLLECTION_NAME')
        total_docs = collection.count()
        print(f'Found collection \"{collection.name}\" with {total_docs} documents')
        
        if total_docs == 0:
            print('Collection is empty - all files will be new')
            open('$EXISTING_FILES_LIST', 'w').close()
        else:
            # Get all existing file paths in batches
            all_existing_paths = set()
            batch_size = 1000
            
            print(f'Retrieving existing file paths in batches of {batch_size}...')
            
            for offset in range(0, total_docs, batch_size):
                try:
                    batch = collection.get(
                        include=['metadatas'],
                        limit=batch_size,
                        offset=offset
                    )
                    
                    if not batch['ids']:
                        break
                    
                    # Extract file paths from metadata
                    batch_paths = 0
                    for metadata in batch['metadatas']:
                        if metadata and 'file_path' in metadata:
                            all_existing_paths.add(metadata['file_path'])
                            batch_paths += 1
                    
                    print(f'  Batch {offset//batch_size + 1}: {len(batch[\"ids\"])} docs, {batch_paths} with file_path')
                    
                except Exception as e:
                    print(f'Error in batch starting at {offset}: {e}')
                    break
            
            # Write existing file paths to temp file (only files that still exist on filesystem)
            import os
            existing_and_current = []
            for path in all_existing_paths:
                if os.path.exists(path):
                    existing_and_current.append(path)
            
            with open('$EXISTING_FILES_LIST', 'w') as f:
                for path in sorted(existing_and_current):
                    f.write(path + '\\n')
            
            print(f'Found {len(all_existing_paths)} existing file paths in ChromaDB')
            print(f'Found {len(existing_and_current)} files that still exist on filesystem')
        
    except Exception as e:
        if 'does not exist' in str(e) or 'Collection' in str(e):
            print(f'Collection \"$COLLECTION_NAME\" does not exist - will create it')
            try:
                collection = client.create_collection('$COLLECTION_NAME')
                print(f'Created new collection: {collection.name}')
            except Exception as create_error:
                print(f'Error creating collection: {create_error}')
                # Collection might already exist, try to get it again
                try:
                    collection = client.get_collection('$COLLECTION_NAME')
                    print(f'Collection {collection.name} exists after all')
                except:
                    print('Failed to create or access collection')
                    sys.exit(1)
            open('$EXISTING_FILES_LIST', 'w').close()
        else:
            raise e
        
except Exception as e:
    print(f'Error connecting to ChromaDB: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1 | tee -a "$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "❌ Failed to query ChromaDB for existing files"
    exit 1
fi

# Analyze file differences
echo ""
echo "Analyzing file differences..."
# Count total files of the store type
find_files "$INPUT_PATH" "/tmp/all_files_count_${COLLECTION_NAME}.txt"
total_files=$(wc -l < "/tmp/all_files_count_${COLLECTION_NAME}.txt" | tr -d ' ')
existing_count=$([ -f "$EXISTING_FILES_LIST" ] && wc -l < "$EXISTING_FILES_LIST" || echo "0")

echo "Found $total_files total files in input directory (store type: $STORE_TYPE)"
echo "Found $existing_count files already in ChromaDB"

# Find NEW files that aren't in ChromaDB
NEW_FILES_LIST="/tmp/new_files_${COLLECTION_NAME}_$(date +%s).txt"
if [ -f "$EXISTING_FILES_LIST" ] && [ -s "$EXISTING_FILES_LIST" ]; then
    # Use Python to find files in input directory but not in ChromaDB (more reliable than comm)
    find_files "$INPUT_PATH" "/tmp/all_files_${COLLECTION_NAME}.txt"
    
    python3 -c "
# Read both files and find the difference using sets
with open('/tmp/all_files_${COLLECTION_NAME}.txt', 'r') as f:
    all_files = set(line.strip() for line in f)

with open('$EXISTING_FILES_LIST', 'r') as f:
    existing_files = set(line.strip() for line in f)

new_files = all_files - existing_files

with open('$NEW_FILES_LIST', 'w') as f:
    for path in sorted(new_files):
        f.write(path + '\n')
    "
    rm -f "/tmp/all_files_${COLLECTION_NAME}.txt"
else
    # No existing files, so all files are new
    find_files "$INPUT_PATH" "$NEW_FILES_LIST"
fi

new_files_count=$(wc -l < "$NEW_FILES_LIST" | tr -d ' ')
echo "Found $new_files_count NEW files to upload"

if [ "$new_files_count" -eq 0 ]; then
    echo ""
    echo "🎉 All files are already uploaded! ChromaDB is up to date."
    rm -f "$EXISTING_FILES_LIST" "$NEW_FILES_LIST"
    exit 0
fi

# Apply upload limit if specified
if [ -n "$UPLOAD_LIMIT" ] && [ "$new_files_count" -gt "$UPLOAD_LIMIT" ]; then
    echo "Limiting upload to first $UPLOAD_LIMIT files (out of $new_files_count total new files)"
    head -n "$UPLOAD_LIMIT" "$NEW_FILES_LIST" > "${NEW_FILES_LIST}.limited"
    mv "${NEW_FILES_LIST}.limited" "$NEW_FILES_LIST"
    new_files_count="$UPLOAD_LIMIT"
fi

echo ""
if [ "$DRY_RUN" = "true" ]; then
    echo "🔍 DRY RUN: Analyzing $new_files_count files for chunk size optimization..."
    echo ""

    # Dry-run analysis function
    analyze_file_chunks() {
        local file_path="$1"
        local filename=$(basename "$file_path")
        echo "Analyzing: $filename"

        # Create a simple analysis script
        python3 -c "
import os
import sys

file_path = sys.argv[1]
store_type = sys.argv[2]
chunk_size = int(sys.argv[3])
chunk_overlap = int(sys.argv[4])
filename = os.path.basename(file_path)

# Read file content
try:
    if store_type == 'pdf':
        # For dry run, just read as text if it's actually a text file
        # In real scenario, we'd use pymupdf
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                text = f.read()
        except:
            # Estimate based on file size for binary PDFs
            file_size = os.path.getsize(file_path)
            estimated_chars = file_size // 2  # Rough estimate
            text = 'x' * estimated_chars
    else:
        # Source code or documentation
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                text = f.read()
        except UnicodeDecodeError:
            with open(file_path, 'r', encoding='latin-1') as f:
                text = f.read()

    # Token-aware chunking simulation with improved ratio
    chars_per_token = 3.5  # Improved approximation
    chunk_size_chars = int(chunk_size * chars_per_token)
    overlap_chars = int(chunk_overlap * chars_per_token)

    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size_chars
        chunk = text[start:end]
        if chunk.strip():
            chunks.append(len(chunk))
        start = end - overlap_chars
        if start >= len(text):
            break

    file_size = os.path.getsize(file_path)
    total_chars = len(text)
    chunk_count = len(chunks)
    largest_chunk = max(chunks) if chunks else 0
    avg_chunk = sum(chunks) // len(chunks) if chunks else 0

    # Analyze if chunks are too large
    problematic = largest_chunk > 50000  # 50KB limit
    batch_payload = sum(chunks[:50])  # First 50 chunks (default batch size)

    print(f'  File size: {file_size:,} bytes')
    print(f'  Text length: {total_chars:,} chars')
    print(f'  Chunks: {chunk_count}')
    print(f'  Avg chunk: {avg_chunk:,} chars')
    print(f'  Largest chunk: {largest_chunk:,} chars')
    print(f'  Batch payload (50 chunks): {batch_payload:,} chars')

    if problematic:
        print(f'  ⚠️  POTENTIAL ISSUE: Largest chunk > 50KB')
        # Suggest better chunk size
        target_chunk_size = max(500, int(40000 / chars_per_token))  # 40KB target
        print(f'  💡 SUGGESTION: --chunk-size {target_chunk_size}')
        sys.exit(1)
    else:
        print(f'  ✓ Chunks look good')
        sys.exit(0)

except Exception as e:
    print(f'  ❌ Error analyzing {filename}: {e}')
    sys.exit(1)
" "$file_path" "$STORE_TYPE" "$CHUNK_SIZE" "$CHUNK_OVERLAP"

        return $?
    }

    # Analyze files
    problem_count=0
    total_analyzed=0

    while IFS= read -r file_path; do
        if analyze_file_chunks "$file_path"; then
            echo ""
        else
            ((problem_count++))
            echo ""
        fi
        ((total_analyzed++))

        # Limit analysis for performance
        if [ "$total_analyzed" -ge 20 ]; then
            echo "... (analyzed first 20 files for performance)"
            break
        fi
    done < "$NEW_FILES_LIST"

    echo "📊 DRY RUN SUMMARY:"
    echo "Files analyzed: $total_analyzed"
    echo "Potential problems: $problem_count"

    if [ "$problem_count" -gt 0 ]; then
        echo ""
        echo "💡 RECOMMENDATIONS:"
        echo "1. Reduce chunk size: --chunk-size 1000 --batch-size 25"
        echo "2. Use dry-run with adjusted settings to verify improvements"
        echo "3. Consider excluding very large minified files"
    else
        echo "✅ Current settings should work well!"
    fi

    exit 0
fi

echo "Starting upload of $new_files_count new files..."

# Function to process a single PDF file
process_pdf_file() {
    local pdf_file="$1"
    local file_number="$2"
    local total_files="$3"
    local collection_name="$4"
    local chroma_host="$5"
    local chroma_port="$6"
    local log_file="$7"
    local client_type="$8"
    local data_dir="$9"
    
    local filename=$(basename "$pdf_file")
    echo "[$file_number/$total_files] Processing: $filename"
    
    # Create Python script for this specific PDF (unique temp file per process)
    local temp_script="/tmp/upload_pdf_$$_${file_number}.py"
    cat > "$temp_script" << 'EOF'
import chromadb
import fitz  # pymupdf
import sys
import os
from pathlib import Path

try:
    pdf_path = sys.argv[1]
    collection_name = sys.argv[2]
    client_type = sys.argv[3]
    chroma_host = sys.argv[4] if len(sys.argv) > 4 else 'localhost'
    chroma_port = int(sys.argv[5]) if len(sys.argv) > 5 else 9000
    data_dir = sys.argv[6] if len(sys.argv) > 6 else './chroma_data'
    chunk_size = int(sys.argv[7]) if len(sys.argv) > 7 else 3000
    chunk_overlap = int(sys.argv[8]) if len(sys.argv) > 8 else 600
    embedding_model = sys.argv[9] if len(sys.argv) > 9 else 'stella'
    ocr_enabled = sys.argv[10] if len(sys.argv) > 10 else 'true'
    ocr_engine = sys.argv[11] if len(sys.argv) > 11 else 'tesseract'
    ocr_language = sys.argv[12] if len(sys.argv) > 12 else 'eng'
    store_type = sys.argv[13] if len(sys.argv) > 13 else 'pdf'
    batch_size = int(sys.argv[14]) if len(sys.argv) > 14 else 50
    filename = os.path.basename(pdf_path)

    # Get git metadata for source-code files
    git_metadata = {}
    if store_type == 'source-code':
        # Find the git project root for this file
        current_dir = os.path.dirname(os.path.abspath(pdf_path))
        git_root = None

        # Walk up the directory tree to find .git
        while current_dir != '/':
            if os.path.exists(os.path.join(current_dir, '.git')):
                git_root = current_dir
                break
            parent = os.path.dirname(current_dir)
            if parent == current_dir:  # Reached root
                break
            current_dir = parent

        if git_root:
            try:
                import subprocess
                os.chdir(git_root)

                # Get git metadata
                commit_hash = subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                    stderr=subprocess.DEVNULL).decode().strip()

                try:
                    remote_url = subprocess.check_output(['git', 'remote', 'get-url', 'origin'],
                                                       stderr=subprocess.DEVNULL).decode().strip()
                except subprocess.CalledProcessError:
                    remote_url = 'unknown'

                try:
                    branch = subprocess.check_output(['git', 'branch', '--show-current'],
                                                   stderr=subprocess.DEVNULL).decode().strip()
                except subprocess.CalledProcessError:
                    branch = 'unknown'

                git_metadata = {
                    'git_project_root': git_root,
                    'git_commit_hash': commit_hash,
                    'git_remote_url': remote_url,
                    'git_branch': branch,
                    'git_project_name': os.path.basename(git_root)
                }

                print(f'Git project: {git_metadata["git_project_name"]} (commit: {commit_hash[:8]})')

            except (subprocess.CalledProcessError, FileNotFoundError):
                print(f'Warning: Could not get git metadata for {pdf_path}')
            finally:
                # Change back to original directory
                os.chdir(os.path.dirname(pdf_path))

    # Extract text based on store type
    text = ''
    extraction_method = 'unknown'

    if store_type == 'pdf':
        # Extract text with pymupdf
        doc = fitz.open(pdf_path)

        # Extract text from all pages
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            page_text = page.get_text()
            if page_text.strip():
                text += page_text + '\n'

        doc.close()
        extraction_method = 'pymupdf'

    elif store_type in ['source-code', 'markdown']:
        # Read text files directly
        try:
            with open(pdf_path, 'r', encoding='utf-8') as f:
                text = f.read()
            extraction_method = 'direct_read'
        except UnicodeDecodeError:
            try:
                with open(pdf_path, 'r', encoding='latin-1') as f:
                    text = f.read()
                extraction_method = 'direct_read_latin1'
            except Exception as e:
                print(f'Error reading file {pdf_path}: {e}')
                sys.exit(1)
        except Exception as e:
            print(f'Error reading file {pdf_path}: {e}')
            sys.exit(1)

    # OCR fallback for image PDFs (only applicable to PDF store type)
    ocr_confidence = None
    is_image_pdf = False

    if store_type == 'pdf' and not text.strip():
        if ocr_enabled.lower() == 'true':
            print(f'No text found, attempting OCR with {ocr_engine} engine...')
            is_image_pdf = True

            # Check OCR dependencies first
            ocr_available = False
            try:
                if ocr_engine == 'tesseract':
                    import pytesseract
                    # Quick test of tesseract binary
                    pytesseract.get_tesseract_version()
                    ocr_available = True
                elif ocr_engine == 'easyocr':
                    import easyocr
                    ocr_available = True
            except Exception as dep_error:
                print(f'OCR dependencies not available: {dep_error}')
                print(f'Skipping OCR for {pdf_path}')
                sys.exit(3)  # Special exit code for no text

            if not ocr_available:
                print(f'OCR engine {ocr_engine} not available')
                print(f'Skipping OCR for {pdf_path}')
                sys.exit(3)

            try:
                # Re-open document for OCR
                doc = fitz.open(pdf_path)
                ocr_text_parts = []
                confidence_scores = []

                for page_num in range(len(doc)):
                    page = doc.load_page(page_num)
                    # Convert page to image
                    pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0))  # 2x scale for better OCR
                    img_data = pix.tobytes("png")

                    if ocr_engine == 'tesseract':
                        import pytesseract
                        from PIL import Image
                        import io

                        # Convert to PIL Image
                        image = Image.open(io.BytesIO(img_data))

                        # Perform OCR with confidence data
                        try:
                            data = pytesseract.image_to_data(image, lang=ocr_language, output_type=pytesseract.Output.DICT)
                            page_text = pytesseract.image_to_string(image, lang=ocr_language)

                            # Calculate average confidence for this page
                            confidences = [int(conf) for conf in data['conf'] if int(conf) > 0]
                            if confidences:
                                confidence_scores.extend(confidences)

                        except Exception as e:
                            print(f'  Warning: OCR failed for page {page_num + 1}: {e}')
                            page_text = ''

                    elif ocr_engine == 'easyocr':
                        import easyocr
                        import numpy as np
                        from PIL import Image
                        import io

                        # Convert to numpy array for EasyOCR
                        image = Image.open(io.BytesIO(img_data))
                        img_array = np.array(image)

                        try:
                            reader = easyocr.Reader([ocr_language])
                            results = reader.readtext(img_array, detail=1)  # Get confidence scores

                            page_text = ' '.join([result[1] for result in results])
                            page_confidences = [result[2] * 100 for result in results]  # Convert to percentage
                            confidence_scores.extend(page_confidences)

                        except Exception as e:
                            print(f'  Warning: OCR failed for page {page_num + 1}: {e}')
                            page_text = ''

                    else:
                        page_text = ''

                    if page_text.strip():
                        ocr_text_parts.append(page_text)
                        print(f'  Page {page_num + 1}: {len(page_text)} characters extracted')

                doc.close()

                # Combine all OCR text
                text = '\\n'.join(ocr_text_parts)

                if text.strip():
                    extraction_method = f'ocr_{ocr_engine}'
                    if confidence_scores:
                        ocr_confidence = sum(confidence_scores) / len(confidence_scores)
                        print(f'OCR completed: {len(text)} characters, avg confidence: {ocr_confidence:.1f}%')
                    else:
                        print(f'OCR completed: {len(text)} characters')
                else:
                    print(f'OCR failed to extract any text from {pdf_path}')
                    sys.exit(3)  # Special exit code for no text

            except ImportError as e:
                print(f'OCR library not available: {e}')
                print(f'Install with: pip install {ocr_engine}')
                sys.exit(3)
            except Exception as e:
                print(f'OCR processing failed: {e}')
                sys.exit(3)
        else:
            print(f'No text extracted from {pdf_path} (OCR disabled)')
            sys.exit(3)  # Special exit code for no text

    # Model-specific token-aware chunking without remote dependencies
    def chunk_text_token_aware(text, chunk_size_tokens=460, overlap_tokens=46, model_name=None):
        '''
        Chunk text based on model-specific character-to-token ratios.
        Uses researched ratios for each embedding model without remote fetching.
        '''
        # Model-specific character-to-token ratios based on research
        model_char_ratios = {
            'stella': 3.2,      # BERT-based, WordPiece tokenizer
            'modernbert': 3.4,  # Modern BERT with improved tokenization
            'bge-large': 3.3,   # BERT-based, similar to Stella
            'default': 3.5      # all-MiniLM-L6-v2, sentence-transformers default
        }

        chars_per_token = model_char_ratios.get(model_name, 3.5)
        chunk_size_chars = int(chunk_size_tokens * chars_per_token)
        overlap_chars = int(overlap_tokens * chars_per_token)

        chunks = []
        start = 0

        while start < len(text):
            end = start + chunk_size_chars
            chunk = text[start:end]

            if chunk.strip():
                chunks.append(chunk)

            # Move start position with overlap
            start = end - overlap_chars
            if start >= len(text):
                break

        print(f'Model-optimized chunking ({model_name}): {len(chunks)} chunks, ~{chunk_size_tokens} tokens each ({chars_per_token} chars/token)')
        return chunks

    # Markdown heading-aware chunking
    def chunk_markdown_heading_aware(text, chunk_size_tokens=430, model_name=None):
        '''
        Chunk markdown text based on heading structure while respecting token limits.
        Tries to keep sections together, splits at subsection boundaries when needed.
        '''
        try:
            import mistune
            import re
        except ImportError:
            print('Mistune not available, falling back to token-aware chunking')
            # Use smaller overlap for markdown
            overlap_tokens = max(20, chunk_size_tokens // 20)
            return chunk_text_token_aware(text, chunk_size_tokens, overlap_tokens, model_name)

        # Model-specific character-to-token ratios
        model_char_ratios = {
            'stella': 3.2,
            'modernbert': 3.4,
            'bge-large': 3.3,
            'default': 3.5
        }
        chars_per_token = model_char_ratios.get(model_name, 3.5)
        max_chunk_chars = int(chunk_size_tokens * chars_per_token)

        # Parse markdown using mistune's proper GFM-compliant parser
        md_parser = mistune.create_markdown(renderer='ast')
        ast = md_parser(text)

        def extract_text(node):
            '''Recursively extract text from AST node'''
            if isinstance(node, dict):
                if node.get('type') == 'text':
                    return node.get('raw', '')
                elif 'children' in node:
                    return ''.join(extract_text(child) for child in node['children'])
            return ''

        # Extract ALL headings from AST
        expected_headings = []
        for node in ast:
            if node.get('type') == 'heading':
                expected_headings.append({
                    'level': node['attrs']['level'],
                    'title': extract_text(node).strip()
                })

        # Find heading positions by testing each line with mistune
        lines = text.split('\n')
        heading_positions = []
        heading_idx = 0  # Track which heading we're looking for

        i = 0
        while i < len(lines) and heading_idx < len(expected_headings):
            # Test if current line (plus next for setext) forms a heading
            test_lines = [lines[i]]
            if i + 1 < len(lines):
                test_lines.append(lines[i + 1])

            test_text = '\n'.join(test_lines)
            test_ast = md_parser(test_text)

            # Check if mistune found a heading
            for node in test_ast:
                if node.get('type') == 'heading':
                    found_title = extract_text(node).strip()
                    found_level = node['attrs']['level']

                    # Match against next expected heading
                    if (heading_idx < len(expected_headings) and
                        expected_headings[heading_idx]['title'] == found_title and
                        expected_headings[heading_idx]['level'] == found_level):
                        heading_positions.append({
                            'line': i,
                            'level': found_level,
                            'title': found_title
                        })
                        heading_idx += 1
                        break

            i += 1

        # Build sections from heading positions
        sections = []
        if not heading_positions:
            sections.append({
                'level': 0,
                'title': 'Document Start',
                'content': text
            })
        else:
            # Add content before first heading
            if heading_positions[0]['line'] > 0:
                pre_lines = lines[:heading_positions[0]['line']]
                if any(line.strip() for line in pre_lines):
                    sections.append({
                        'level': 0,
                        'title': 'Document Start',
                        'content': '\n'.join(pre_lines) + '\n'
                    })

            # Add each heading section
            for idx, heading in enumerate(heading_positions):
                start_line = heading['line']
                if idx + 1 < len(heading_positions):
                    end_line = heading_positions[idx + 1]['line']
                else:
                    end_line = len(lines)

                section_lines = lines[start_line:end_line]
                sections.append({
                    'level': heading['level'],
                    'title': heading['title'],
                    'content': '\n'.join(section_lines) + '\n'
                })

        # Build chunks respecting section boundaries
        chunks = []
        chunk_metadata = []  # Store metadata for each chunk
        current_chunk = ''
        current_headings = []

        def add_chunk(content, headings):
            if content.strip():
                chunks.append(content)
                chunk_metadata.append({
                    'headings': headings.copy(),
                    'primary_heading': headings[-1] if headings else 'Document',
                    'section_depth': len(headings)
                })

        for section in sections:
            section_content = section['content']
            section_heading = section['title']
            section_level = section['level']

            # Update heading hierarchy
            if section_level > 0:
                # Trim hierarchy to current level
                current_headings = [h for h in current_headings if h['level'] < section_level]
                current_headings.append({'level': section_level, 'title': section_heading})

            # Check if adding this section would exceed chunk size
            potential_chunk = current_chunk + section_content

            if len(potential_chunk) <= max_chunk_chars:
                # Section fits in current chunk
                current_chunk = potential_chunk
            else:
                # Section doesn't fit
                if current_chunk:
                    # Save current chunk
                    add_chunk(current_chunk, current_headings)

                # Check if section itself is too large
                if len(section_content) > max_chunk_chars:
                    # Split large section into smaller chunks with overlap
                    overlap_chars = int(chars_per_token * 20)  # 20 token overlap
                    start = 0
                    while start < len(section_content):
                        end = start + max_chunk_chars
                        chunk_content = section_content[start:end]
                        add_chunk(chunk_content, current_headings)
                        start = end - overlap_chars
                        if start >= len(section_content):
                            break
                    current_chunk = ''
                else:
                    # Start new chunk with this section
                    current_chunk = section_content

        # Add remaining chunk
        if current_chunk:
            add_chunk(current_chunk, current_headings)

        # Return chunks with metadata
        print(f'Markdown heading-aware chunking ({model_name}): {len(chunks)} chunks, ~{chunk_size_tokens} tokens each')
        print(f'  Preserved {sum(1 for m in chunk_metadata if m["section_depth"] > 0)} section boundaries')

        return chunks, chunk_metadata

    # Chunk the text based on store type
    if store_type == 'source-code':
        # Use ASTChunk for source code
        try:
            from astchunk import ASTChunkBuilder

            # Detect language based on file extension
            file_ext = os.path.splitext(pdf_path)[1].lower()
            language_map = {
                '.py': 'python',
                '.java': 'java',
                '.js': 'typescript',  # ASTChunk uses typescript parser for JS
                '.ts': 'typescript',
                '.tsx': 'typescript',
                '.jsx': 'typescript',
                '.cs': 'csharp',
                '.go': 'go',
                '.rs': 'rust',
                '.cpp': 'cpp',
                '.c': 'c',
                '.php': 'php',
                '.rb': 'ruby'
            }

            language = language_map.get(file_ext, 'python')  # Default to python

            # Configure ASTChunk
            configs = {
                'max_chunk_size': int(chunk_size * 3.2 * 0.50),  # Very conservative char estimate: tokens * chars_per_token * safety_buffer
                'language': language,
                'metadata_template': 'default',
                'chunk_overlap': 0,  # Disable overlap to prevent size inflation
                'chunk_expansion': False  # Avoid token-consuming metadata headers
            }
            chunk_builder = ASTChunkBuilder(**configs)

            # Use ASTChunk to chunk source code
            chunks_data = chunk_builder.chunkify(text, **configs)
            chunks = [chunk_item['content'] for chunk_item in chunks_data]
            extraction_method = f'astchunk_{language}'
            print(f'Split into {len(chunks)} AST-aware chunks for {language} code (max_size={chunk_size} tokens, ~{int(chunk_size * 3.2 * 0.50)} chars)')

        except ImportError:
            print('ASTChunk not available, falling back to token-aware chunking')
            chunks = chunk_text_token_aware(text, chunk_size, chunk_overlap, embedding_model)
        except Exception as e:
            print(f'ASTChunk failed ({e}), falling back to token-aware chunking')
            chunks = chunk_text_token_aware(text, chunk_size, chunk_overlap, embedding_model)

    elif store_type == 'markdown' and pdf_path.endswith('.md'):
        # Use heading-aware chunking for markdown files
        try:
            chunks, md_chunk_metadata = chunk_markdown_heading_aware(text, chunk_size, embedding_model)
            extraction_method = 'markdown_heading_aware'
            print(f'Split into {len(chunks)} heading-aware chunks for markdown')
        except Exception as e:
            print(f'Markdown heading-aware chunking failed ({e}), falling back to token-aware chunking')
            chunks = chunk_text_token_aware(text, chunk_size, chunk_overlap, embedding_model)
            md_chunk_metadata = None
    else:
        # Use token-aware chunking for PDF and other markdown files
        chunks = chunk_text_token_aware(text, chunk_size, chunk_overlap, embedding_model)
        md_chunk_metadata = None
    print(f'Using server-side embedding model: {embedding_model}')

    # Validate chunk sizes against model limits
    def validate_chunk_sizes(chunks, model_name, max_tokens):
        '''Validate that chunks do not exceed model token limits'''
        if not chunks:
            return

        # Get model-specific limits
        model_limits = {
            'stella': 512,
            'bge-large': 512,
            'default': 512,
            'modernbert': 8192
        }

        model_limit = model_limits.get(model_name, 512)
        oversized_chunks = 0

        # For token-aware chunks, we know they're within limits by design
        # But for character-based fallback or AST chunks, we should warn
        for i, chunk in enumerate(chunks):
            # Rough token estimate for validation (3.5 chars per token)
            estimated_tokens = len(chunk) / 3.5

            if estimated_tokens > model_limit:
                oversized_chunks += 1
                if oversized_chunks <= 3:  # Show first 3 warnings
                    print(f'⚠️  Chunk {i+1} estimated at {int(estimated_tokens)} tokens (exceeds {model_limit} limit for {model_name})')

        if oversized_chunks > 3:
            print(f'⚠️  {oversized_chunks - 3} additional chunks may exceed token limits')

        if oversized_chunks > 0:
            print(f'💡 Consider reducing chunk size or using --chunk-size auto for model optimization')

    # Validate the chunks
    validate_chunk_sizes(chunks, embedding_model, chunk_size)

    # Connect to ChromaDB using appropriate client
    if client_type == 'remote':
        client = chromadb.HttpClient(host=chroma_host, port=chroma_port)
    else:
        client = chromadb.PersistentClient(path=data_dir)
    
    # Get or create collection
    try:
        collection = client.get_collection(collection_name)
    except ValueError:
        collection = client.create_collection(collection_name)
    
    # Generate unique base ID from file path (consistent across runs)
    import hashlib
    base_file_id = hashlib.sha256(pdf_path.encode()).hexdigest()[:12]

    # Check if any chunks from this document already exist
    try:
        existing = collection.get(
            where={"file_path": pdf_path},
            include=['metadatas']
        )
        if existing['ids']:
            print(f'Document chunks already exist: {filename} ({len(existing["ids"])} chunks)')
            sys.exit(2)  # Special exit code for already exists
    except:
        pass  # Document doesn't exist, continue

    # Get current timestamp
    from datetime import datetime
    upload_date = datetime.now().isoformat()

    # Prepare and add chunks
    chunk_ids = []
    chunk_documents = []
    chunk_metadatas = []

    for i, chunk in enumerate(chunks):
        chunk_id = f"{base_file_id}_chunk_{i:03d}"
        chunk_ids.append(chunk_id)
        chunk_documents.append(chunk)

        # Prepare metadata for each chunk
        chunk_metadata = {
            'filename': filename,
            'file_path': pdf_path,
            'file_size': os.path.getsize(pdf_path),
            'upload_date': upload_date,
            'text_extraction_method': extraction_method,
            'text_length': len(text),
            'chunk_index': i,
            'chunk_count': len(chunks),
            'chunk_size_tokens': chunk_size,
            'chunk_overlap_tokens': chunk_overlap,
            'chunk_length': len(chunk),
            'embedding_model': embedding_model,
            'storage': f'{chroma_host}:{chroma_port}' if client_type == 'remote' else data_dir,
            'full_document': False,
            'is_chunked': True,
            'is_new_upload': True,
            'store_type': store_type,
        }

        # Add store-specific metadata
        if store_type == 'pdf':
            chunk_metadata.update({
                'is_image_pdf': is_image_pdf,
                'ocr_enabled': ocr_enabled.lower() == 'true',
                'ocr_engine': ocr_engine if is_image_pdf else '',
                'ocr_language': ocr_language if is_image_pdf else '',
                'ocr_confidence': ocr_confidence if ocr_confidence is not None else 0.0
            })

        elif store_type == 'source-code':
            file_ext = os.path.splitext(pdf_path)[1].lower()
            language_map = {
                '.py': 'python', '.java': 'java', '.js': 'javascript',
                '.ts': 'typescript', '.tsx': 'typescript', '.jsx': 'javascript',
                '.cs': 'csharp', '.go': 'go', '.rs': 'rust',
                '.cpp': 'cpp', '.c': 'c', '.php': 'php', '.rb': 'ruby',
                '.kt': 'kotlin', '.scala': 'scala', '.swift': 'swift'
            }

            chunk_metadata.update({
                'programming_language': language_map.get(file_ext, 'unknown'),
                'file_extension': file_ext,
                'ast_chunked': 'astchunk' in extraction_method if hasattr(locals(), 'extraction_method') else False,
                'has_functions': 'def ' in chunk or 'function ' in chunk or 'public ' in chunk,
                'has_classes': 'class ' in chunk or 'interface ' in chunk,
                'has_imports': 'import ' in chunk or 'from ' in chunk or '#include' in chunk,
                'line_count': len(chunk.split('\n')),
            })

            # Add git metadata for source-code files
            if git_metadata:
                chunk_metadata.update({
                    'git_project_root': git_metadata['git_project_root'],
                    'git_commit_hash': git_metadata['git_commit_hash'],
                    'git_remote_url': git_metadata['git_remote_url'],
                    'git_branch': git_metadata['git_branch'],
                    'git_project_name': git_metadata['git_project_name']
                })

        elif store_type == 'markdown':
            doc_metadata = {
                'doc_type': 'markdown' if pdf_path.endswith('.md') else 'text',
                'has_code_blocks': '```' in chunk or '    ' in chunk,  # Simple heuristic
                'has_links': '[' in chunk and '](' in chunk,
                'line_count': len(chunk.split('\n')),
            }

            # Add markdown-specific metadata if available
            if md_chunk_metadata and i < len(md_chunk_metadata):
                md_meta = md_chunk_metadata[i]
                # Extract heading titles from the list of heading dicts
                heading_titles = [h['title'] if isinstance(h, dict) else str(h) for h in md_meta.get('headings', [])]
                primary = md_meta.get('primary_heading', 'Document')
                primary_title = primary['title'] if isinstance(primary, dict) else str(primary)

                doc_metadata.update({
                    'markdown_headings': ' > '.join(heading_titles) if heading_titles else '',
                    'markdown_primary_heading': primary_title,
                    'markdown_section_depth': md_meta.get('section_depth', 0),
                    'markdown_heading_aware': True,
                })

            chunk_metadata.update(doc_metadata)
        chunk_metadatas.append(chunk_metadata)

    # Add chunks to collection in batches to avoid payload size limits
    # ChromaDB HTTP client has payload limits, so batch large files
    # batch_size is passed as parameter from command line (default 50)

    for i in range(0, len(chunks), batch_size):
        batch_end = min(i + batch_size, len(chunks))
        batch_documents = chunk_documents[i:batch_end]
        batch_metadatas = chunk_metadatas[i:batch_end]
        batch_ids = chunk_ids[i:batch_end]

        try:
            collection.add(
                documents=batch_documents,
                metadatas=batch_metadatas,
                ids=batch_ids
            )
            if len(chunks) > batch_size:
                print(f'  Uploaded batch {i//batch_size + 1}/{(len(chunks) + batch_size - 1)//batch_size}: {len(batch_documents)} chunks')
        except Exception as batch_error:
            error_msg = str(batch_error)

            # Check if it's a payload size error
            if 'payload too large' in error_msg.lower() or '413' in error_msg:
                print(f'❌ PAYLOAD TOO LARGE ERROR')
                print(f'📁 File: {pdf_path}')
                print(f'📊 File size: {os.path.getsize(pdf_path):,} bytes')
                print(f'🧩 Total chunks: {len(chunks)}')
                print(f'📦 Batch size: {batch_size} chunks')
                print(f'💾 Batch payload: ~{sum(len(doc) for doc in batch_documents):,} characters')
                print()

                # Find the largest chunks in this batch for analysis
                chunk_sizes = [(len(batch_documents[j]), batch_ids[j]) for j in range(len(batch_documents))]
                chunk_sizes.sort(reverse=True)  # Largest first

                print('🔍 Largest chunks in failed batch:')
                for size, chunk_id in chunk_sizes[:3]:  # Show top 3
                    print(f'   {chunk_id}: {size:,} chars')
                print()

                # Calculate suggested chunk size (aim for max 10KB per chunk)
                max_chunk_size = max(size for size, _ in chunk_sizes)
                target_chunk_chars = 10000  # 10KB target
                suggested_tokens = max(500, int(target_chunk_chars / 4))  # ~4 chars per token

                print('💡 RECOMMENDATIONS:')
                print(f'   Current chunk size: {chunk_size} tokens')
                print(f'   Largest chunk generated: {max_chunk_size:,} chars')
                print(f'   Suggested chunk size: {suggested_tokens} tokens')
                print(f'   Suggested batch size: 25 (current: {batch_size})')
                print()
                print('🔧 RECOVERY OPTIONS:')
                print('   1. Reduce chunk size and batch size:')
                print(f'      --chunk-size {suggested_tokens} --batch-size 25')

                # Add project deletion option for source-code store
                if store_type == 'source-code' and git_metadata:
                    project_name = git_metadata.get('git_project_name', 'unknown')
                    print(f'   2. Delete partial project and retry:')
                    print(f'      --delete-project {project_name}')

                print('   3. Skip this file and continue:')
                print('      Add file to exclusion list (manual)')
                print()
                print(f'❌ STOPPING: Cannot upload {filename} - chunks too large')

                # Exit with specific code for payload errors
                sys.exit(4)  # New exit code for payload errors

            else:
                # Non-payload error, re-raise
                print(f'Error uploading batch {i//batch_size + 1}: {error_msg}')
                raise batch_error

    print(f'Successfully uploaded: {filename} ({len(chunks)} chunks, {len(text)} total chars)')
    
except Exception as e:
    print(f'Error processing {pdf_path}: {str(e)}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

    # Run the Python script (capture exit code properly)
    python3 "$temp_script" "$pdf_file" "$collection_name" "$client_type" "$chroma_host" "$chroma_port" "$data_dir" "$CHUNK_SIZE" "$CHUNK_OVERLAP" "$EMBEDDING_MODEL" "$OCR_ENABLED" "$OCR_ENGINE" "$OCR_LANGUAGE" "$STORE_TYPE" "$BATCH_SIZE" 2>&1 | tee -a "$log_file"
    local python_exit_code=${PIPESTATUS[0]}
    
    # Clean up temp file
    rm -f "$temp_script"
    
    if [ $python_exit_code -eq 0 ]; then
        echo "  ✓ Success: $filename"
        return 0
    elif [ $python_exit_code -eq 2 ]; then
        echo "  ⚠ Already exists (skipped): $filename"
        return 0
    elif [ $python_exit_code -eq 3 ]; then
        echo "  ⚪ No text extracted: $filename"
        return 3
    elif [ $python_exit_code -eq 4 ]; then
        echo "  💥 Payload too large: $filename"
        return 4  # Payload error - this will trigger failure handling
    else
        echo "  ✗ Failed: $filename"
        return 1
    fi
}

# Export the function so it can be used by parallel processes
export -f process_pdf_file

# Initialize counters
success_count=0
error_count=0

# Process files in parallel using xargs
echo "Processing files with $MAX_PARALLEL_JOBS parallel jobs..."

# Create a temporary file to store results
RESULT_FILE="/tmp/upload_results_$(date +%s)_$$.txt"
# Clean up any old result files
rm -f /tmp/upload_results_*.txt

# Process files in parallel using background processes
pids=()
line_number=1
while IFS= read -r pdf_file; do
    # Wait if we have reached the maximum number of parallel jobs
    while [ ${#pids[@]} -ge $MAX_PARALLEL_JOBS ]; do
        # Wait for any process to complete instead of polling
        wait -n  # Wait for next process to complete

        # Clean up completed processes from pids array
        new_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=("$pid")
            fi
        done
        pids=("${new_pids[@]}")
    done

    # Start background process
    (
        process_pdf_file "$pdf_file" "$line_number" "$new_files_count" "$COLLECTION_NAME" "$CHROMA_HOST" "$CHROMA_PORT" "$LOG_FILE" "$CLIENT_TYPE" "$CHROMA_DATA_DIR"
        echo $? >> "$RESULT_FILE"
    ) &
    pids+=($!)

    ((line_number++))
done < "$NEW_FILES_LIST"

# Wait for all remaining background processes to complete
for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        wait "$pid"
    fi
done

# Count results
if [ -f "$RESULT_FILE" ]; then
    success_count=$(grep -c "^0$" "$RESULT_FILE" 2>/dev/null || echo "0")
    error_count=$(grep -c "^1$" "$RESULT_FILE" 2>/dev/null || echo "0")
    no_text_count=$(grep -c "^3$" "$RESULT_FILE" 2>/dev/null || echo "0")
    payload_error_count=$(grep -c "^4$" "$RESULT_FILE" 2>/dev/null || echo "0")

    # Clean variables immediately after assignment
    success_count=${success_count//[^0-9]/}
    error_count=${error_count//[^0-9]/}
    no_text_count=${no_text_count//[^0-9]/}
    payload_error_count=${payload_error_count//[^0-9]/}

    # Handle payload errors - if any files failed due to size, stop here
    if [ "${payload_error_count:-0}" -gt 0 ]; then
        echo ""
        echo "💥 UPLOAD STOPPED: $payload_error_count file(s) failed due to payload size limits"
        echo ""
        echo "🔧 WHAT TO DO:"
        echo "1. Check the error details above for specific recommendations"
        echo "2. Use smaller chunk sizes: --chunk-size 800 --batch-size 25"
        echo "3. If this is a git project and you want to clean up partial uploads:"
        echo "   Re-run with --delete-project PROJECT_NAME to remove partial data"
        echo ""

        # Auto-delete failed project if requested and we can identify it
        if [ "$DELETE_FAILED_PROJECT" = "true" ] && [ "$STORE_TYPE" = "source-code" ]; then
            echo "🗑️ Auto-deleting failed projects (--delete-failed-project enabled)..."

            # Try to identify failed projects from the log
            failed_projects=$(grep -E "git_project_name.*:" "$LOG_FILE" | tail -5 | cut -d: -f2 | sort -u | tr -d ' ')

            if [ -n "$failed_projects" ]; then
                for project in $failed_projects; do
                    echo "Deleting project: $project"
                    # Use the same deletion logic as above
                    python3 -c "
import chromadb

try:
    if '$CLIENT_TYPE' == 'remote':
        client = chromadb.HttpClient(host='$CHROMA_HOST', port=$CHROMA_PORT)
    else:
        client = chromadb.PersistentClient(path='$CHROMA_DATA_DIR')

    collection = client.get_collection('$COLLECTION_NAME')
    existing_docs = collection.get(where={'git_project_name': '$project'}, include=['metadatas'], limit=10)

    if existing_docs['ids']:
        # Delete all chunks for this project
        all_project_ids = []
        batch_size = 1000
        offset = 0

        while True:
            batch = collection.get(where={'git_project_name': '$project'}, include=['metadatas'], limit=batch_size, offset=offset)
            if not batch['ids']: break
            all_project_ids.extend(batch['ids'])
            offset += batch_size
            if len(batch['ids']) < batch_size: break

        if all_project_ids:
            for i in range(0, len(all_project_ids), 100):
                batch_ids = all_project_ids[i:i+100]
                collection.delete(ids=batch_ids)
            print(f'Deleted {len(all_project_ids)} chunks from project $project')

except Exception as e:
    print(f'Error deleting project $project: {e}')
"
                done
                echo "✅ Failed projects cleaned up. You can now retry with adjusted parameters."
            fi
        fi

        rm -f "$RESULT_FILE"
        exit 2  # Exit with error code for payload failures
    fi

    rm -f "$RESULT_FILE"
else
    success_count=0
    error_count=0
    no_text_count=0
    payload_error_count=0
fi

# Set defaults for empty variables (cleanup already done above)
success_count=${success_count:-0}
error_count=${error_count:-0}
no_text_count=${no_text_count:-0}
payload_error_count=${payload_error_count:-0}

processed_files=$new_files_count

# Clean up temp files
rm -f "$EXISTING_FILES_LIST" "$NEW_FILES_LIST"

echo ""
echo "🎉 Smart upload completed!"
echo "New files processed: $new_files_count"
echo "Successfully uploaded: $success_count"
if [ "$no_text_count" -gt 0 ]; then
    echo "No text extracted (image-only PDFs): $no_text_count"
fi
if [ "$payload_error_count" -gt 0 ]; then
    echo "Payload too large errors: $payload_error_count"
fi
echo "Other errors: $error_count"
echo "Full log saved to: $LOG_FILE"

# Final collection stats
echo ""
echo "Checking final collection statistics..."
python3 -c "
import chromadb
import time

try:
    print('Connecting to ChromaDB...', end='', flush=True)
    start_time = time.time()

    if '$CLIENT_TYPE' == 'remote':
        client = chromadb.HttpClient(host='$CHROMA_HOST', port=$CHROMA_PORT)
    else:
        client = chromadb.PersistentClient(path='$CHROMA_DATA_DIR')

    print(f' ({time.time() - start_time:.1f}s)')

    print('Getting collection info...', end='', flush=True)
    start_time = time.time()
    collection = client.get_collection('$COLLECTION_NAME')
    total_docs = collection.count()
    print(f' ({time.time() - start_time:.1f}s)')

    print(f'Collection: {collection.name}')
    print(f'Total documents: {total_docs}')

    # Skip the slow new document count query for faster completion
    print(f'Documents added in this session: $success_count files processed')
    # Note: Could enable detailed counting with --verbose flag in future

    print('✅ ChromaDB is now up to date!')
    print('📊 Next run will only process newly added files.')

except Exception as e:
    print(f'Error getting collection stats: {e}')
"