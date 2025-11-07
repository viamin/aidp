# Update the RUBY_VERSION arg in compose.yaml
ARG RUBY_VERSION=3.4.7
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# Switch to root for system package installation
USER root

# Set timezone
ARG TZ=UTC
ENV TZ=${TZ}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install system dependencies
RUN apt-get update && apt-get install -y \
  # Development tools
  build-essential \
  cmake \
  curl \
  git \
  libssh2-1-dev \
  libssl-dev \
  pkg-config \
  libtree-sitter-dev \
  vim \
  # Networking tools
  dnsutils \
  ipset \
  iptables \
  jq \
  netcat-openbsd \
  # Shell improvements
  fzf \
  ripgrep \
  tmux \
  zsh \
  # Yamllint for config validation
  yamllint \
  # Process management
  procps \
  # CA certificates utilities
  ca-certificates \
  # Clean up
  && rm -rf /var/lib/apt/lists/*

# Install git-delta for better diffs (handle multi-arch)
ARG DELTA_VERSION=0.18.2
RUN ARCH="$(dpkg --print-architecture)" \
  && case "$ARCH" in \
  amd64|arm64) DELTA_ARCH="$ARCH" ;; \
  *) echo "Unsupported architecture for git-delta: $ARCH" >&2 && exit 1 ;; \
  esac \
  && wget "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb" \
  && dpkg -i "git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb" \
  && rm "git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb"

# Copy firewall initialization script
COPY .devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

# Optional: custom root CA bundle install
# Place custom CA cert(s) in .devcontainer/custom-ca/ (PEM files). They will be added if present.
COPY .devcontainer/custom-ca/ /tmp/custom-ca/
RUN if [ -d /tmp/custom-ca ] && ls /tmp/custom-ca/*.pem >/dev/null 2>&1; then \
  echo "Installing custom CA certificates"; \
  cp /tmp/custom-ca/*.pem /usr/local/share/ca-certificates/; \
  update-ca-certificates; \
  else \
  echo "No custom CA certificates found"; \
  fi

# Node / other tooling can also use NODE_EXTRA_CA_CERTS to point to a bundled file if needed.

# Grant vscode user sudo access to init-firewall.sh without password (USER switched later)
RUN echo "vscode ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/vscode-firewall && chmod 0440 /etc/sudoers.d/vscode-firewall

# Ensure binding is always 0.0.0.0
# Binds the server to all IP addresses of the container, so it can be accessed from outside the container.
ENV BINDING="0.0.0.0"

# Switch to base image user (vscode) for development
USER vscode
WORKDIR /workspaces/aidp

# mise is installed via devcontainer feature (ghcr.io/devcontainers-extra/features/mise:1)
# Configure PATH to include mise shims so Ruby/gem commands work seamlessly
ENV PATH="/home/vscode/.local/share/mise/shims:/home/vscode/.local/bin:$PATH"
