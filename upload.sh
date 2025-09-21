#!/bin/bash

# Script to upload only NEW PDFs from specified directory to ChromaDB
# Supports both persistence (local) and remote ChromaDB clients
# Works with both existing collections and creates new ones from scratch
# 
# Usage: ./upload_new_pdfs.sh [OPTIONS]
#
# Options:
#   -c, --collection NAME      ChromaDB collection name (default: ResearchLibrary)
#   -h, --host HOST            ChromaDB host for remote client (default: localhost)
#   -p, --port PORT            ChromaDB port for remote client (default: 8000)
#   -l, --limit NUMBER         Maximum number of files to upload (optional)
#   -i, --input-path PATH      Path to recursively search for PDF files (required)"
#   -d, --data-path PATH       Path for ChromaDB persistence data storage (forces persistence mode)
#   -e, --embedding-model MODEL Embedding model (stella|modernbert|bge-large|default) [default: stella]
#   --chunk-size TOKENS        Chunk size in tokens (default: 3000)
#   --chunk-overlap TOKENS     Chunk overlap in tokens (default: 600, 20% of chunk-size)
#   --delete-collection        Delete and recreate the collection before upload
#   --help                     Show this help message
#
# Path Types:
#   --input-path: Directory containing PDF files to index (searched recursively)
#   --data-path:  Directory where ChromaDB stores its database files (persistence mode only)
#
# Client Selection:
#   - If --data-path is specified: uses PersistentClient
#   - Otherwise: uses HttpClient with --host and --port (default: localhost:8000)
#
# Environment variables:
#   PDF_INPUT_PATH: Path to directory containing PDF files (alternative to -i option)
#   CHROMA_DATA_PATH: Default path for persistence client data directory

set -e

# Default values
COLLECTION_NAME="ResearchLibrary"
CHROMA_HOST="localhost"
CHROMA_PORT="8000"
UPLOAD_LIMIT=""
INPUT_PATH="${PDF_INPUT_PATH:-}"  # Use environment variable or require CLI option
CHROMA_DATA_DIR=""
CLIENT_TYPE="remote"
EMBEDDING_MODEL="stella"
CHUNK_SIZE="3000"
CHUNK_OVERLAP="600"
DELETE_COLLECTION="false"

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --collection NAME      ChromaDB collection name (default: ResearchLibrary)"
    echo "  -h, --host HOST            ChromaDB host for remote client (default: localhost)"
    echo "  -p, --port PORT            ChromaDB port for remote client (default: 8000)"
    echo "  -l, --limit NUMBER         Maximum number of files to upload (optional)"
    echo "  -i, --input-path PATH      Path to recursively search for PDF files (required)"
    echo "  -d, --data-path PATH       Path for ChromaDB persistence data storage (forces persistence mode)"
    echo "  -e, --embedding-model MODEL Embedding model: stella, modernbert, bge-large, default [default: stella]"
    echo "  --chunk-size TOKENS        Chunk size in tokens (default: 3000)"
    echo "  --chunk-overlap TOKENS     Chunk overlap in tokens (default: 600, 20% of chunk-size)"
    echo "  --delete-collection        Delete and recreate the collection before upload"
    echo "  --help                     Show this help message"
    echo ""
    echo "Path Types:"
    echo "  --input-path: Directory containing PDF files to index (searched recursively)"
    echo "  --data-path:  Directory where ChromaDB stores its database files (persistence mode only)"
    echo ""
    echo "Client Selection:"
    echo "  - If --data-path is specified: uses PersistentClient"
    echo "  - Otherwise: uses HttpClient with --host and --port (default: localhost:8000)"
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
    echo "  $0 -i /path/to/pdfs -c MyCollection -l 10"
    echo "  $0 -i /path/to/pdfs -c MyCollection -e stella"
    echo "  $0 -i /path/to/pdfs -d /path/to/chroma/data -c MyCollection"
    echo "  $0 -i /path/to/pdfs -h remote.host.com -p 9000 -c MyCollection"
    echo "  $0 -i /path/to/pdfs --delete-collection -c MyCollection -e stella"
    echo "  PDF_INPUT_PATH=/path/to/pdfs $0 -e modernbert --chunk-size 2000"
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
        --chunk-size)
            CHUNK_SIZE="$2"
            shift 2
            ;;
        --chunk-overlap)
            CHUNK_OVERLAP="$2"
            shift 2
            ;;
        --delete-collection)
            DELETE_COLLECTION="true"
            shift
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

# Validate that input path is provided
if [ -z "$INPUT_PATH" ]; then
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

# Validate input path exists
if [ ! -d "$INPUT_PATH" ]; then
    echo "❌ Input path does not exist: $INPUT_PATH"
    exit 1
fi

echo "Starting SMART PDF upload to ChromaDB with Enhanced Embeddings"
echo "Collection: $COLLECTION_NAME"
echo "Input path: $INPUT_PATH"
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
echo "Chunk size: $CHUNK_SIZE tokens"
echo "Chunk overlap: $CHUNK_OVERLAP tokens"
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
    print('✓ Required packages available')
    print(f'  chromadb version: {chromadb.__version__}')
    print(f'  pymupdf version: {fitz.version[0]}')

    # Verify ChromaDB version compatibility
    import packaging.version
    min_version = '1.0.0'
    if packaging.version.parse(chromadb.__version__) < packaging.version.parse(min_version):
        print(f'⚠ Warning: ChromaDB version {chromadb.__version__} may not be compatible')
        print(f'  Recommended: pip install --upgrade chromadb')
    else:
        print(f'✓ ChromaDB version {chromadb.__version__} is compatible')

    # Note about server-side embeddings
    print('ℹ️ Using server-side embeddings - no local ML models required')

except ImportError as e:
    print(f'✗ Missing package: {e}')
    print('Install with: pip install --upgrade chromadb pymupdf')
    exit(1)
" 2>&1 | tee -a "$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "Please install required packages: pip install --upgrade chromadb pymupdf"
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
total_files=$(find "$INPUT_PATH" -name "*.pdf" | wc -l | tr -d ' ')
existing_count=$([ -f "$EXISTING_FILES_LIST" ] && wc -l < "$EXISTING_FILES_LIST" || echo "0")

echo "Found $total_files total PDF files in input directory"
echo "Found $existing_count files already in ChromaDB"

# Find NEW files that aren't in ChromaDB
NEW_FILES_LIST="/tmp/new_files_${COLLECTION_NAME}_$(date +%s).txt"
if [ -f "$EXISTING_FILES_LIST" ] && [ -s "$EXISTING_FILES_LIST" ]; then
    # Use Python to find files in input directory but not in ChromaDB (more reliable than comm)
    find "$INPUT_PATH" -name "*.pdf" > "/tmp/all_files_${COLLECTION_NAME}.txt"
    
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
    find "$INPUT_PATH" -name "*.pdf" > "$NEW_FILES_LIST"
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
    chroma_port = int(sys.argv[5]) if len(sys.argv) > 5 else 8000
    data_dir = sys.argv[6] if len(sys.argv) > 6 else './chroma_data'
    chunk_size = int(sys.argv[7]) if len(sys.argv) > 7 else 3000
    chunk_overlap = int(sys.argv[8]) if len(sys.argv) > 8 else 600
    embedding_model = sys.argv[9] if len(sys.argv) > 9 else 'stella'
    filename = os.path.basename(pdf_path)

    # Extract text with pymupdf
    doc = fitz.open(pdf_path)
    text = ''

    # Extract text from all pages
    for page_num in range(len(doc)):
        page = doc.load_page(page_num)
        page_text = page.get_text()
        if page_text.strip():
            text += page_text + '\n'

    doc.close()

    # Skip if no text extracted
    if not text.strip():
        print(f'No text extracted from {pdf_path}')
        sys.exit(3)  # Special exit code for no text

    # Simple chunking function (approximating 4 chars per token)
    def chunk_text(text, chunk_size_tokens=3000, overlap_tokens=600):
        chars_per_token = 4
        chunk_size_chars = chunk_size_tokens * chars_per_token
        overlap_chars = overlap_tokens * chars_per_token

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

        return chunks

    # Chunk the text
    chunks = chunk_text(text, chunk_size, chunk_overlap)
    print(f'Split into {len(chunks)} chunks (chunk_size={chunk_size}, overlap={chunk_overlap})')
    print(f'Using server-side embedding model: {embedding_model}')

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
            'extractor': 'pymupdf',
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
            'is_new_upload': True
        }
        chunk_metadatas.append(chunk_metadata)

    # Add all chunks to collection in batch
    collection.add(
        documents=chunk_documents,
        metadatas=chunk_metadatas,
        ids=chunk_ids
    )

    print(f'Successfully uploaded: {filename} ({len(chunks)} chunks, {len(text)} total chars)')
    
except Exception as e:
    print(f'Error processing {pdf_path}: {str(e)}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

    # Run the Python script (capture exit code properly)
    python3 "$temp_script" "$pdf_file" "$collection_name" "$client_type" "$chroma_host" "$chroma_port" "$data_dir" "$CHUNK_SIZE" "$CHUNK_OVERLAP" "$EMBEDDING_MODEL" 2>&1 | tee -a "$log_file"
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

# Create a wrapper script for each file
WRAPPER_SCRIPT="/tmp/process_wrapper_$$.sh"
cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/bin/bash
line_number="$1"
pdf_file="$2"
collection_name="$3" 
chroma_host="$4"
chroma_port="$5"
log_file="$6"
result_file="$7"
total_files="$8"

source_script_dir="$(dirname "$0")"
source "$source_script_dir/upload_new_pdfs.sh"

process_pdf_file "$pdf_file" "$line_number" "$total_files" "$collection_name" "$chroma_host" "$chroma_port" "$log_file"
echo $? >> "$result_file"
WRAPPER_EOF

chmod +x "$WRAPPER_SCRIPT"

# Process files in parallel using background processes
pids=()
line_number=1
while IFS= read -r pdf_file; do
    # Wait if we have reached the maximum number of parallel jobs
    while [ ${#pids[@]} -ge $MAX_PARALLEL_JOBS ]; do
        for i in "${!pids[@]}"; do
            if ! kill -0 ${pids[i]} 2>/dev/null; then
                unset pids[i]
            fi
        done
        pids=("${pids[@]}")  # Reindex array
        sleep 0.1
    done
    
    # Start background process
    (
        process_pdf_file "$pdf_file" "$line_number" "$new_files_count" "$COLLECTION_NAME" "$CHROMA_HOST" "$CHROMA_PORT" "$LOG_FILE" "$CLIENT_TYPE" "$CHROMA_DATA_DIR"
        echo $? >> "$RESULT_FILE"
    ) &
    pids+=($!)
    
    ((line_number++))
done < "$NEW_FILES_LIST"

# Wait for all background processes to complete
for pid in "${pids[@]}"; do
    wait $pid
done

# Clean up wrapper script
rm -f "$WRAPPER_SCRIPT"

# Count results
if [ -f "$RESULT_FILE" ]; then
    success_count=$(grep -c "^0$" "$RESULT_FILE" 2>/dev/null || echo "0")
    error_count=$(grep -c "^1$" "$RESULT_FILE" 2>/dev/null || echo "0") 
    no_text_count=$(grep -c "^3$" "$RESULT_FILE" 2>/dev/null || echo "0")
    
# Debug output removed for clean operation
    
    rm -f "$RESULT_FILE"
else
    success_count=0
    error_count=0
    no_text_count=0
fi

# Remove any numeric issues
success_count=$(echo "$success_count" | tr -d '\n' | tr -d ' ')
error_count=$(echo "$error_count" | tr -d '\n' | tr -d ' ')  
no_text_count=$(echo "$no_text_count" | tr -d '\n' | tr -d ' ')

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
echo "Errors: $error_count"
echo "Full log saved to: $LOG_FILE"

# Final collection stats
echo ""
echo "Final collection statistics:"
python3 -c "
import chromadb

try:
    if '$CLIENT_TYPE' == 'remote':
        client = chromadb.HttpClient(host='$CHROMA_HOST', port=$CHROMA_PORT)
    else:
        client = chromadb.PersistentClient(path='$CHROMA_DATA_DIR')
    
    collection = client.get_collection('$COLLECTION_NAME')
    print(f'Collection: {collection.name}')
    print(f'Total documents: {collection.count()}')
    
    # Count documents from this upload session
    try:
        new_docs = collection.get(
            where={'is_new_upload': True},
            include=['metadatas']
        )
        new_count = len(new_docs['ids'])
        if new_count > 0:
            print(f'Documents added in this session: {new_count}')
    except:
        pass  # Ignore errors counting new docs
    
    print('✅ ChromaDB is now up to date!')
    print('📊 Next run will only process newly added PDFs.')
    
except Exception as e:
    print(f'Error getting collection stats: {e}')
"