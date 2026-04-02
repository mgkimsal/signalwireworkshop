FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/go/bin:${PATH}"

# ── Add external repos (NodeSource for Node 20, ngrok) ─────────────────────
RUN apt-get update \
    && apt-get install -y ca-certificates curl gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
       | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
       | tee /etc/apt/sources.list.d/ngrok.list \
    && rm -rf /var/lib/apt/lists/*

# ── Install all language runtimes and tools ─────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Base tools
    git curl wget jq build-essential lsof \
    # Python 3.12
    python3 python3-venv python3-pip \
    # Node.js 20 (from NodeSource)
    nodejs \
    # Ruby + Bundler
    ruby-full \
    # Perl + CPAN
    perl cpanminus libssl-dev \
    # Java 21
    openjdk-21-jdk-headless \
    # C++ toolchain
    cmake g++ libcurl4-openssl-dev nlohmann-json3-dev \
    # ngrok
    ngrok \
    && gem install bundler --no-document \
    && rm -rf /var/lib/apt/lists/*

# ── Go (official tarball — apt version is too old) ──────────────────────────
ARG GO_VERSION=1.23.6
RUN GO_ARCH=$(dpkg --print-architecture) \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    && tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    && rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

WORKDIR /workshop

EXPOSE 3000

CMD ["bash"]
