FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/go/bin:${PATH}"

# ── Add external repos (NodeSource, Microsoft .NET, ngrok) ─────────────────
RUN apt-get update \
    && apt-get install -y ca-certificates curl gnupg wget \
    # NodeSource for Node.js 20
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    # Microsoft .NET repo
    && wget -q "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" \
       -O /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb && rm /tmp/packages-microsoft-prod.deb \
    # ngrok repo
    && curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
       | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
       | tee /etc/apt/sources.list.d/ngrok.list \
    && rm -rf /var/lib/apt/lists/*

# ── Install all language runtimes and tools ─────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Base tools
    git curl wget jq build-essential lsof screen \
    # Python 3.12
    python3 python3-venv python3-pip \
    # Node.js 20 (from NodeSource)
    nodejs \
    # Ruby + Bundler
    ruby-full \
    # Perl + CPAN + SSL modules (pre-built to avoid compile issues)
    perl cpanminus libssl-dev libnet-ssleay-perl libio-socket-ssl-perl \
    # Java 21
    openjdk-21-jdk-headless \
    # C++ toolchain
    cmake g++ libcurl4-openssl-dev nlohmann-json3-dev \
    # .NET 8.0
    dotnet-sdk-8.0 \
    # PHP + extensions
    php-cli php-mbstring php-xml php-curl \
    # ngrok
    ngrok \
    && gem install bundler --no-document \
    # Composer for PHP
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && rm -rf /var/lib/apt/lists/*

# ── Go (official tarball — apt version is too old) ──────────────────────────
ARG GO_VERSION=1.23.6
RUN GO_ARCH=$(dpkg --print-architecture) \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    && tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    && rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

# ── Non-root user ───────────────────────────────────────────────────────────
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} devuser 2>/dev/null || true \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash devuser 2>/dev/null \
    || useradd -m -s /bin/bash devuser

WORKDIR /workshop

EXPOSE 3000

USER devuser
CMD ["bash"]
