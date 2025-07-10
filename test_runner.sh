#!/bin/bash

# 🧪 Nosmai Flutter Test Runner
# Professional test suite for comprehensive plugin testing

echo "🚀 Starting Nosmai Flutter Test Suite..."
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test file
run_test() {
    local test_file=$1
    local test_name=$2
    
    echo -e "${BLUE}🧪 Running $test_name...${NC}"
    
    if flutter test $test_file --coverage; then
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ $test_name FAILED${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
}

# Navigate to plugin directory
cd "$(dirname "$0")"

echo -e "${YELLOW}📋 Checking Flutter environment...${NC}"
flutter doctor --version
echo ""

echo -e "${YELLOW}📦 Getting dependencies...${NC}"
flutter pub get
echo ""

echo -e "${YELLOW}🧪 Running Test Suite...${NC}"
echo "================================================"

# Run individual test files
run_test "test/nosmai_camera_sdk_test.dart" "Core Functionality Tests"
run_test "test/types_test.dart" "Type System Tests"
run_test "test/performance_test.dart" "Performance & Stress Tests"
run_test "test/nosmai_camera_sdk_method_channel_test.dart" "Method Channel Tests"

# Run all tests together for coverage
echo -e "${BLUE}🧪 Running Complete Test Suite with Coverage...${NC}"
if flutter test --coverage; then
    echo -e "${GREEN}✅ Complete Test Suite PASSED${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}❌ Complete Test Suite FAILED${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

echo ""
echo "================================================"
echo -e "${YELLOW}📊 Test Results Summary${NC}"
echo "================================================"
echo -e "Total Tests: ${BLUE}$TOTAL_TESTS${NC}"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

# Calculate success rate
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo -e "Success Rate: ${BLUE}$SUCCESS_RATE%${NC}"
fi

echo ""

# Generate coverage report if lcov is available
if command -v lcov &> /dev/null && [ -f "coverage/lcov.info" ]; then
    echo -e "${YELLOW}📈 Generating Coverage Report...${NC}"
    
    # Generate HTML coverage report
    if command -v genhtml &> /dev/null; then
        genhtml coverage/lcov.info -o coverage/html
        echo -e "${GREEN}✅ Coverage report generated at: coverage/html/index.html${NC}"
    fi
    
    # Show coverage summary
    lcov --summary coverage/lcov.info
fi

echo ""

# Final result
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! Plugin is ready for production! 🚀${NC}"
    exit 0
else
    echo -e "${RED}💥 $FAILED_TESTS test(s) failed. Please fix issues before release.${NC}"
    exit 1
fi