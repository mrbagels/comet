#!/usr/bin/env bash

set -euo pipefail

xcrun simctl list devices available --json | ruby -rjson -e '
  preferred_names = ARGV.empty? ? ["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 15 Pro"] : ARGV
  devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
  candidates = devices.select { |device| device["isAvailable"] && device["name"].start_with?("iPhone") }
  device = preferred_names.lazy.map { |name| candidates.find { |candidate| candidate["name"] == name } }.find(&:itself) || candidates.first
  abort("No available iPhone simulator found.") unless device
  puts device["udid"]
' "$@"
