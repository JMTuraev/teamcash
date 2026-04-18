#!/bin/zsh

# Source this file before working on the project:
#   source tools/macos/use-local-toolchain.zsh

export TEAMCASH_LOCAL_TOOLCHAIN_ROOT="$HOME/.local/teamcash-tools"
export FLUTTER_ROOT="$TEAMCASH_LOCAL_TOOLCHAIN_ROOT/flutter"
export TEAMCASH_NODE_ROOT="$TEAMCASH_LOCAL_TOOLCHAIN_ROOT/node-v22.22.2-darwin-arm64"
export JAVA_HOME="$TEAMCASH_LOCAL_TOOLCHAIN_ROOT/jdk-17.0.18+8/Contents/Home"
export TEAMCASH_RUBY_ROOT="$HOME/.local/ruby/3.3.11"
export GEM_HOME="$HOME/.local/ruby/gems/3.3.11"
export GEM_PATH="$GEM_HOME:$TEAMCASH_RUBY_ROOT/lib/ruby/gems/3.3.0"
export SSL_CERT_FILE="/etc/ssl/cert.pem"
export SSL_CERT_DIR="/etc/ssl/certs"

export PATH="$FLUTTER_ROOT/bin:$TEAMCASH_NODE_ROOT/bin:$JAVA_HOME/bin:$TEAMCASH_RUBY_ROOT/bin:$GEM_HOME/bin:$PATH"
