#!/bin/bash
# Download, package, and sign the latest version of the buildkite-agent

RELEASE_INFO_URL="https://buildkite.com/agent/releases/latest?platform=darwin&arch=arm64&system=darwin&machine=arm64"
LATEST_RELEASE=$(curl -s "$RELEASE_INFO_URL")
LATEST_VERSION=$(echo "$LATEST_RELEASE" | awk -F= '/version=/  { print $2 }')
SIGNED_PACKAGE_DESTINATION="build/buildkite-agent-$LATEST_VERSION.pkg"

function set_signing_identites {
  output="$(/usr/bin/security find-identity -p macappstore -v)"

  BINARY_SIGNING_IDENTITY=$(echo "$output" | awk -F'"' '{print $2}' | awk NF | grep 'Apple Distribution' | fzf --prompt "Select your Apple Distribution certificate: ")

  if [ -z "$BINARY_SIGNING_IDENTITY" ]; then
    log_error "No Apple Distribution certificate selected"
    exit 1
  fi

  log "Selected binary signing identity: $BINARY_SIGNING_IDENTITY"

  INSTALLER_SIGNING_IDENTITY=$(echo "$output" | awk -F'"' '{print $2}' | awk NF | grep 'Developer ID Installer' | fzf --prompt "Select your Developer ID Installer certificate: ")

  if [ -z "$INSTALLER_SIGNING_IDENTITY" ]; then
    log_error "No Developer ID Installer certificate selected"
    exit 1
  fi

  log "Selected installer signing identity: $INSTALLER_SIGNING_IDENTITY"
}

function get_package_identifier {
  read -r -p 'Enter the package identifier to use (reverse DNS format, e.g. com.apple.developer): ' PACKAGE_IDENTIFIER

  if [[ -z $PACKAGE_IDENTIFIER ]]; then
    log_error "No package identifier provided"
    exit 1
  fi
}

function main() {
  local destination; destination="src"

  get_package_identifier

  set_signing_identites

  rm -rf "$destination"

  log "Downloading latest version of Buildkite"
  DESTINATION="$destination" bash -c "$(curl -sL https://raw.githubusercontent.com/buildkite/agent/main/install.sh)"

  sign_binary

  create_package

  open "build"
  log "$SIGNED_PACKAGE_DESTINATION is ready to upload and distribute"
}

function update_package_metadata {
  local file; file="$1"
  sed -i '' "s/com.example.buildkite-agent/$PACKAGE_IDENTIFIER/g" "$file"
  sed -i '' "s/placeholder-version-number/$LATEST_VERSION/g" "$file"
}

function sign_binary {
  local path_to_buildkite_agent; path_to_buildkite_agent="src/bin/buildkite-agent"

  log "Signing downloaded binary: $path_to_buildkite_agent"
  log "Using: $BINARY_SIGNING_IDENTITY"

  (/usr/bin/codesign --sign "$BINARY_SIGNING_IDENTITY" --identifier "$PACKAGE_IDENTIFIER" "$path_to_buildkite_agent" && \
    log "Signed: $path_to_buildkite_agent") || \
    log_error "Unable to sign $path_to_buildkite_agent with $BINARY_SIGNING_IDENTITY"

  codesign -dr - "$path_to_buildkite_agent"
}

function create_package {
  log "Creating package"

  pkgbuild --root ./src/bin \
    --install-location '/opt/buildkite/bin' \
    --identifier "$PACKAGE_IDENTIFIER" \
    --version "$LATEST_VERSION" \
    --sign "$INSTALLER_SIGNING_IDENTITY" \
    "./build/buildkite-agent-$LATEST_VERSION.pkg"
}

function log {
  prefix="${2:-INFO}"

  echo
  echo "$prefix -- $1"
}

function log_error {
  log "$1" "ERROR"
}

main
