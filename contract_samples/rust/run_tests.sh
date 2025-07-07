#!/bin/bash

# Test runner script for Amadeus Deposit Contract
set -e

echo "🚀 Running Amadeus Deposit Contract Tests"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "Cargo.toml" ]; then
    print_error "Cargo.toml not found. Please run this script from the rust contract directory."
    exit 1
fi

# Clean previous builds
print_status "Cleaning previous builds..."
cargo clean

# Check if code compiles
print_status "Checking code compilation..."
if cargo check; then
    print_success "Code compiles successfully"
else
    print_error "Code compilation failed"
    exit 1
fi

# Run unit tests
print_status "Running unit tests..."
if cargo test --lib; then
    print_success "Unit tests passed"
else
    print_error "Unit tests failed"
    exit 1
fi

# Run integration tests
print_status "Running integration tests..."
if cargo test --test integration_tests -- --test-threads=1; then
    print_success "Integration tests passed"
else
    print_error "Integration tests failed"
    exit 1
fi

# Run tests with different features
print_status "Running tests with different configurations..."

# Test with debug build
print_status "Testing debug build..."
if cargo test --lib --test integration_tests -- --test-threads=1; then
    print_success "Debug build tests passed"
else
    print_error "Debug build tests failed"
    exit 1
fi

# Test with release build
print_status "Testing release build..."
if cargo test --release --lib --test integration_tests -- --test-threads=1; then
    print_success "Release build tests passed"
else
    print_error "Release build tests failed"
    exit 1
fi

# Run clippy for code quality
print_status "Running clippy for code quality..."
if cargo clippy -- -D warnings; then
    print_success "Clippy passed (no warnings)"
else
    print_warning "Clippy found some issues"
fi

# Run tests with verbose output
print_status "Running tests with verbose output..."
cargo test --verbose

# Generate test coverage report (if tarpaulin is available)
if command -v cargo-tarpaulin &> /dev/null; then
    print_status "Generating test coverage report..."
    if cargo tarpaulin --out Html; then
        print_success "Coverage report generated"
        print_status "Coverage report available in tarpaulin-report.html"
    else
        print_warning "Coverage report generation failed"
    fi
else
    print_warning "cargo-tarpaulin not found. Install with: cargo install cargo-tarpaulin"
fi

# Summary
echo ""
echo "=========================================="
print_success "All tests completed successfully!"
echo ""
print_status "Test Summary:"
echo "  ✅ Unit tests: PASSED"
echo "  ✅ Integration tests: PASSED"
echo "  ✅ Debug build: PASSED"
echo "  ✅ Release build: PASSED"
echo "  ✅ Code compilation: PASSED"
echo ""
print_status "Next steps:"
echo "  1. Review any warnings from clippy"
echo "  2. Check coverage report if generated"
echo "  3. Run: cargo build --release --target wasm32-unknown-unknown"
echo "  4. Deploy the contract"
echo ""

# Optional: Build WASM target
read -p "Do you want to build the WASM target? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Building WASM target..."
    if cargo build --release --target wasm32-unknown-unknown; then
        print_success "WASM build completed successfully"
        print_status "WASM file available in target/wasm32-unknown-unknown/release/"
    else
        print_error "WASM build failed"
        exit 1
    fi
fi

print_success "Test suite completed! 🎉" 