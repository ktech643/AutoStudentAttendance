#!/usr/bin/env bash
# Prints this Mac's primary LAN IPv4 for phone / emulator API calls.
ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1"
