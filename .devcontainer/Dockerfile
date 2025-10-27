# Development container for AIDP
# Provides a sandboxed environment with all necessary tools and providers

ARG RUBY_VERSION=3.4.5
ARG TZ=UTC

FROM ruby:${RUBY_VERSION}

# Set timezone
ARG TZ
ENV TZ=${TZ}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Development tools
    git \
    vim \
    nano \
    curl \
    wget \
    build-essential \
    # Networking tools
    iptables \
    ipset \
    dnsutils \
    netcat-openbsd \
    # Shell improvements
    zsh \
    fzf \
    # Yamllint for config validation
    yamllint \
    # Process management
    procps \
    # Clean up
    && rm -rf /var/lib/apt/lists/*

# Install git-delta for better diffs
ARG DELTA_VERSION=0.18.2
RUN wget https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_amd64.deb \
    && dpkg -i git-delta_${DELTA_VERSION}_amd64.deb \
    && rm git-delta_${DELTA_VERSION}_amd64.deb

# Install mise (asdf successor) for version management
RUN curl https://mise.run | sh
ENV PATH="/root/.local/bin:$PATH"

# Create non-root user
ARG USERNAME=aidp
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

# Set up workspace directory
RUN mkdir -p /workspace && chown -R $USERNAME:$USERNAME /workspace

# Set up .aidp directory for configuration
RUN mkdir -p /home/$USERNAME/.aidp && chown -R $USERNAME:$USERNAME /home/$USERNAME/.aidp

# Set up command history persistence
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir -p /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME:$USERNAME /commandhistory \
    && echo "$SNIPPET" >> /home/$USERNAME/.bashrc

# Install zsh with powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
    -t https://github.com/romkatv/powerlevel10k \
    -p git \
    -p https://github.com/zsh-users/zsh-autosuggestions \
    -p https://github.com/zsh-users/zsh-syntax-highlighting

# Configure fzf key bindings and completion
RUN echo '[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/$USERNAME/.bashrc \
    && echo '[ -f /usr/share/doc/fzf/examples/completion.bash ] && source /usr/share/doc/fzf/examples/completion.bash' >> /home/$USERNAME/.bashrc

# Set nano as default editor
ENV EDITOR=nano

# Copy firewall initialization script
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

# Grant $USERNAME user sudo access to init-firewall.sh without password
RUN echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh" >> /etc/sudoers.d/$USERNAME

# Switch to non-root user
USER $USERNAME
WORKDIR /workspace

# Install Ruby gems globally for development
ENV GEM_HOME="/home/$USERNAME/.gem"
ENV PATH="$GEM_HOME/bin:$PATH"

# Pre-install common development gems
RUN gem install bundler rake rspec rubocop standard

# Install Claude Code CLI (if not using macOS provider)
# Note: This can be customized per-project in devcontainer.json
RUN npm_config_user=root sudo npm install -g @anthropic-ai/claude-code || true

CMD ["/bin/bash"]
