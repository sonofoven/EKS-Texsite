#!/bin/sh

pandoc ../latex/resume.tex -f latex -t html5 -s -o "../nginx/html/index.html" --metadata charset=utf-8
