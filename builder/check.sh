#!/bin/sh
# Glimpse headless checks: syntax gate + fixture regeneration + unit tests.
# Run before calling any change done.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)

echo "== syntax (luac -p) =="
if command -v luac >/dev/null 2>&1; then
    for f in "$HERE"/../plugin/*.lua "$HERE"/scanner_tests.lua; do
        luac -p "$f"
        echo "ok: $f"
    done
else
    echo "luac not found, skipping byte-compilation syntax check"
fi

echo "== fixture =="
python3 "$HERE/make_fixture_epub.py"

echo "== scanner tests =="
if command -v lua >/dev/null 2>&1; then
    lua "$HERE/scanner_tests.lua"
elif command -v luajit >/dev/null 2>&1; then
    luajit "$HERE/scanner_tests.lua"
else
    python3 "$HERE/test_runner.py"
fi

echo "ALL CHECKS PASSED"
