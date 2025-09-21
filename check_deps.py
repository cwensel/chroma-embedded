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

def main():
    print("🔍 Checking ChromaDB Enhanced OCR Dependencies\n")

    # Core dependencies
    print("Core Dependencies:")
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

    if pytesseract_ok and tesseract_binary_ok:
        print("✅ Tesseract ready - OCR available (default engine)")
        print("   Default usage: ./upload.sh -i /path/to/pdfs")
    elif easyocr_ok:
        print("✅ EasyOCR available - OCR will work")
        print("   Use with: --ocr-engine easyocr")
    else:
        print("⚠️  No OCR engine available")
        print("   Install Tesseract: brew install tesseract (macOS)")
        print("   Or install EasyOCR: pip install .[easyocr]")
        print("   Or disable OCR: --disable-ocr")

    print("\n🚀 Ready to upload PDFs with OCR support!")
    print("   Example: ./upload.sh -i /path/to/pdfs -e stella")

    return 0

if __name__ == "__main__":
    sys.exit(main())