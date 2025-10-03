#!/usr/bin/env python3
"""
Dependency checker for chroma-enhanced OCR functionality.
Verifies all required packages and OCR engines are available.
"""

import sys
import subprocess
from importlib import import_module

def check_package(package_name, description=""):
    """Check if a Python package is available."""
    try:
        import_module(package_name)
        print(f"✓ {package_name} - {description}")
        return True
    except ImportError:
        print(f"✗ {package_name} - {description}")
        return False

def check_tesseract():
    """Check if tesseract binary is available."""
    try:
        import pytesseract
        version = pytesseract.get_tesseract_version()
        print(f"✓ tesseract binary - version {version}")
        return True
    except Exception as e:
        print(f"✗ tesseract binary - {e}")
        return False

def check_bash_version():
    """Check if Bash version supports wait -n for parallel processing."""
    try:
        # Try to use the homebrew bash first if available
        bash_paths = ["/opt/homebrew/bin/bash", "/usr/local/bin/bash", "/bin/bash"]

        for bash_path in bash_paths:
            try:
                result = subprocess.run(
                    [bash_path, "--version"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    version_line = result.stdout.split('\n')[0]
                    # Extract version number
                    import re
                    match = re.search(r'version (\d+)\.(\d+)', version_line)
                    if match:
                        major = int(match.group(1))
                        minor = int(match.group(2))

                        if major > 4 or (major == 4 and minor >= 3):
                            print(f"✓ Bash {major}.{minor} at {bash_path} - Supports parallel processing")
                            return True, bash_path, f"{major}.{minor}"
                        else:
                            if bash_path == "/bin/bash":
                                print(f"✗ Bash {major}.{minor} at {bash_path} - Too old for parallel processing (need 4.3+)")
                                return False, bash_path, f"{major}.{minor}"
                            # Keep looking for newer versions
                            continue
            except (subprocess.TimeoutExpired, FileNotFoundError):
                continue

        # No suitable bash found
        return False, "/bin/bash", "unknown"

    except Exception as e:
        print(f"✗ Error checking Bash version: {e}")
        return False, "/bin/bash", "error"

def main():
    print("🔍 Checking ChromaDB Enhanced Dependencies\n")

    # System dependencies
    print("System Dependencies:")
    bash_ok, bash_path, bash_version = check_bash_version()

    # AST chunking for source code
    print("\nSource Code Processing:")
    astchunk_ok = check_package("astchunk", "AST-aware source code chunking")
    if astchunk_ok:
        # Check tree-sitter parsers
        check_package("tree_sitter", "Multi-language parsing support")
        print("  → AST-aware chunking ready for source code!")
    else:
        print("  → Install with: pip install .")

    # Markdown parsing for documentation
    print("\nMarkdown Processing:")
    mistune_ok = check_package("mistune", "Markdown parsing for heading-aware chunking")
    if mistune_ok:
        print("  → Heading-aware chunking ready for markdown!")
    else:
        print("  → Install with: pip install .")

    # Core dependencies
    print("\nCore Dependencies:")
    core_deps = [
        ("chromadb", "ChromaDB vector database"),
        ("fitz", "PyMuPDF for PDF processing"),
        ("PIL", "Pillow for image processing"),
        ("packaging", "Version checking utilities")
    ]

    core_ok = all(check_package(pkg, desc) for pkg, desc in core_deps)

    print("\nOCR Dependencies:")

    # Check Tesseract (default, requires system dependency)
    pytesseract_ok = check_package("pytesseract", "PyTesseract Python wrapper")
    tesseract_binary_ok = False

    if pytesseract_ok:
        tesseract_binary_ok = check_tesseract()
        if tesseract_binary_ok:
            print("  → Tesseract OCR is ready to use!")
        else:
            print("  → Install tesseract binary:")
            print("    macOS: brew install tesseract")
            print("    Ubuntu/Debian: sudo apt-get install tesseract-ocr")
            print("    CentOS/RHEL: sudo yum install tesseract")
    else:
        print("  → Install with: pip install . (already included)")

    # Check EasyOCR (optional, pure Python)
    print("\nOptional EasyOCR:")
    easyocr_ok = check_package("easyocr", "EasyOCR engine (pure Python)")
    if easyocr_ok:
        check_package("numpy", "NumPy (required by EasyOCR)")
        print("  → EasyOCR is ready to use!")
    else:
        print("  → Install with: pip install .[easyocr]")

    # Summary
    print("\n" + "="*50)
    print("📋 SUMMARY:")

    if not core_ok:
        print("❌ Core dependencies missing - run: pip install .")
        return 1

    # Bash version check
    if not bash_ok:
        print("⚠️  Bash version too old for parallel processing")
        print("   Current: Bash {}".format(bash_version))
        print("   Required: Bash 4.3+ for efficient parallel uploads")
        print("   Install: brew install bash (macOS)")
        print("   Note: Script will still work but less efficiently")
    else:
        print("✅ Bash {} - Parallel processing ready".format(bash_version))

    # AST chunking check
    if astchunk_ok:
        print("✅ ASTChunk ready - Source code processing available")
    else:
        print("⚠️  ASTChunk missing - Source code will use basic chunking")
        print("   Install with: pip install .")

    # Markdown parsing check
    if mistune_ok:
        print("✅ Mistune ready - Markdown heading-aware chunking available")
    else:
        print("⚠️  Mistune missing - Markdown will use basic chunking")
        print("   Install with: pip install .")

    # OCR check
    if pytesseract_ok and tesseract_binary_ok:
        print("✅ Tesseract ready - OCR available (default engine)")
        print("   Default usage: ./upload.sh -i /path/to/pdfs --store pdf")
    elif easyocr_ok:
        print("✅ EasyOCR available - OCR will work")
        print("   Use with: --ocr-engine easyocr")
    else:
        print("⚠️  No OCR engine available")
        print("   Install Tesseract: brew install tesseract (macOS)")
        print("   Or install EasyOCR: pip install .[easyocr]")
        print("   Or disable OCR: --disable-ocr")

    print("\n🚀 Ready to process multiple content types!")
    print("   PDFs: ./upload.sh -i /path/to/pdfs --store pdf -e stella")
    print("   Code: ./upload.sh -i /path/to/source --store source-code -e stella")
    print("   Docs: ./upload.sh -i /path/to/docs --store documentation -e stella")

    return 0

if __name__ == "__main__":
    sys.exit(main())