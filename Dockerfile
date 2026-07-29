# Update the RUBY_VERSION arg to match .tool-versions when Ruby is bumped.
ARG RUBY_VERSION=3.4.8
FROM ghcr.io/rails/devcontainer/images/ruby:${RUBY_VERSION}

USER root

ARG TZ=UTC
ARG YQ_VERSION=4.44.3
ARG DELTA_VERSION=0.18.2

ENV TZ=${TZ}

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
  && echo "${TZ}" > /etc/timezone

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    dnsutils \
    fzf \
    git \
    golang \
    gnupg \
    iproute2 \
    jq \
    libffi-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssh2-1-dev \
    libssl-dev \
    libtree-sitter-dev \
    libyaml-dev \
    netcat-openbsd \
    nodejs \
    npm \
    openssh-client \
    pkg-config \
    procps \
    ripgrep \
    sqlite3 \
    tmux \
    vim \
    yamllint \
    zlib1g-dev \
    wget \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

RUN ARCH="$(dpkg --print-architecture)" \
  && wget "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}" -O /usr/local/bin/yq \
  && chmod +x /usr/local/bin/yq

RUN ARCH="$(dpkg --print-architecture)" \
  && case "${ARCH}" in \
    amd64|arm64) DELTA_ARCH="${ARCH}" ;; \
    *) echo "Unsupported architecture for git-delta: ${ARCH}" >&2 && exit 1 ;; \
  esac \
  && wget "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb" \
  && dpkg -i "git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb" \
  && rm "git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb"

RUN gem install bundler:2.7.2

RUN groupadd --gid 1000 aidp \
  && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash aidp

WORKDIR /opt/aidp

COPY Gemfile Gemfile.lock aidp.gemspec README.md LICENSE /opt/aidp/
COPY exe /opt/aidp/exe
COPY lib /opt/aidp/lib
COPY templates /opt/aidp/templates

RUN bundle config set without "development test" \
  && bundle install --jobs 1 --retry 3 \
  && chown -R aidp:aidp /opt/aidp

COPY docker/entrypoint.sh /usr/local/bin/aidp-entrypoint
RUN chmod +x /usr/local/bin/aidp-entrypoint \
  && mkdir -p /workspace /home/aidp/.aidp /home/aidp/.config/gh \
  && chown -R aidp:aidp /workspace /home/aidp

ENV AIDP_ENV=docker \
  AIDP_LOG_LEVEL=info \
  BINDING=0.0.0.0 \
  GH_CONFIG_DIR=/home/aidp/.config/gh \
  HOME=/home/aidp \
  TREE_SITTER_PARSERS=/workspace/.aidp/parsers

USER aidp
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/aidp-entrypoint"]
CMD ["aidp"]
