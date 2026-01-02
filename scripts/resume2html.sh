#!/bin/sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pandoc "${REPO_ROOT}/latex/resume.tex" -f latex -t html5 -s -o "${REPO_ROOT}/nginx/html/index.html" --metadata charset=utf-8
