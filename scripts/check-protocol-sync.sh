#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

PASS=0
FAIL=0
WARN=0

pass()  { ((PASS++)); echo -e "  ${GREEN}✔${RESET} $1"; }
fail()  { ((FAIL++)); echo -e "  ${RED}✘${RESET} $1"; }
warn()  { ((WARN++)); echo -e "  ${YELLOW}⚠${RESET} $1"; }

# ─────────────────────────────────────────────
# 1. Validate JSON Schema
# ─────────────────────────────────────────────
echo -e "\n${BOLD}1. JSON Schema${RESET}"

SCHEMA="$REPO_ROOT/protocol/schema/messages.json"
if [ ! -f "$SCHEMA" ]; then
    fail "schema file not found: $SCHEMA"
else
    if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$SCHEMA" 2>/dev/null; then
        pass "protocol/schema/messages.json is valid JSON"
    else
        fail "protocol/schema/messages.json is not valid JSON"
    fi
fi

# ─────────────────────────────────────────────
# 2. Validate example payloads
# ─────────────────────────────────────────────
echo -e "\n${BOLD}2. Example Payloads${RESET}"

EXAMPLES_DIR="$REPO_ROOT/protocol/examples"
if [ ! -d "$EXAMPLES_DIR" ]; then
    fail "examples directory not found: $EXAMPLES_DIR"
else
    EXAMPLE_COUNT=0
    for f in "$EXAMPLES_DIR"/*.json; do
        [ -f "$f" ] || continue
        EXAMPLE_COUNT=$((EXAMPLE_COUNT + 1))
        BASENAME="$(basename "$f")"
        if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
            pass "$BASENAME is valid JSON"
        else
            fail "$BASENAME is not valid JSON"
        fi
    done
    if [ "$EXAMPLE_COUNT" -eq 0 ]; then
        fail "no example JSON files found in protocol/examples/"
    fi
fi

# ─────────────────────────────────────────────
# 3. Swift conformance (mac-app)
# ─────────────────────────────────────────────
echo -e "\n${BOLD}3. Swift Conformance (mac-app)${RESET}"

MAC_APP="$REPO_ROOT/mac-app"
if [ ! -f "$MAC_APP/Package.swift" ]; then
    fail "mac-app/Package.swift not found"
else
    echo "  Building mac-app (swift build)..."
    if (cd "$MAC_APP" && swift build 2>&1 | tail -3); then
        pass "swift build succeeded — Codable models compile"
    else
        fail "swift build failed — Codable models may be broken"
    fi
fi

# ─────────────────────────────────────────────
# 4. Kotlin conformance (android-app)
# ─────────────────────────────────────────────
echo -e "\n${BOLD}4. Kotlin Conformance (android-app)${RESET}"

ANDROID_APP="$REPO_ROOT/android-app"
TEST_FILE="$ANDROID_APP/app/src/test/java/com/claudemulti/ProtocolConformanceTest.kt"

if [ ! -f "$TEST_FILE" ]; then
    fail "ProtocolConformanceTest.kt not found"
else
    pass "ProtocolConformanceTest.kt exists"

    if [ -x "$ANDROID_APP/gradlew" ]; then
        echo "  Running Gradle tests..."
        if (cd "$ANDROID_APP" && ./gradlew test 2>&1 | tail -5); then
            pass "./gradlew test passed"
        else
            fail "./gradlew test failed"
        fi
    else
        warn "gradlew not found or not executable — skipping Kotlin tests (run from Android Studio instead)"
    fi
fi

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}────────────────────────────────${RESET}"
echo -e "${BOLD}Summary${RESET}"
echo -e "  ${GREEN}Passed:${RESET}   $PASS"
if [ "$WARN" -gt 0 ]; then
    echo -e "  ${YELLOW}Warnings:${RESET} $WARN"
fi
if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Failed:${RESET}   $FAIL"
    echo -e "${BOLD}────────────────────────────────${RESET}"
    exit 1
fi
echo -e "${BOLD}────────────────────────────────${RESET}"
echo -e "${GREEN}All checks passed.${RESET}"
