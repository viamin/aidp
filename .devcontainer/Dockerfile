# Update the RUBY_VERSION arg in compose.yaml
ARG RUBY_VERSION=3.4.5
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
  nodejs \
  npm \
  pkg-config \
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
  zsh \
  # Yamllint for config validation
  yamllint \
  # Process management
  procps \
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

# Install mise (asdf successor) for version management
RUN curl https://mise.run | sh
ENV PATH="/root/.local/bin:$PATH"

RUN npm install -g markdownlint-cli \
  && npm cache clean --force

# Copy firewall initialization script
COPY .devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

# Grant vscode user sudo access to init-firewall.sh without password (USER switched later)
RUN echo "vscode ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/vscode-firewall && chmod 0440 /etc/sudoers.d/vscode-firewall

# Switch to base image user (vscode) for development
USER vscode
WORKDIR /workspaces/aidp

# Ensure binding is always 0.0.0.0
# Binds the server to all IP addresses of the container, so it can be accessed from outside the container.
ENV BINDING="0.0.0.0"
