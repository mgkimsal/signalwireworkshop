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
    git curl wget jq build-essential lsof screen nano vim \
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

# ── Non-root user (create before cloning so they own the files) ─────────────
RUN useradd -m -s /bin/bash devuser
USER devuser
ENV HOME=/home/devuser
WORKDIR /home/devuser

# ── Clone workshop + all SDKs ──────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/signalwire-demos/workshop.git workshop
WORKDIR /home/devuser/workshop

RUN mkdir -p sdks \
    && git clone --depth 1 https://github.com/signalwire/signalwire-python.git     sdks/signalwire-python \
    && git clone --depth 1 https://github.com/signalwire/signalwire-typescript.git sdks/signalwire-typescript \
    && git clone --depth 1 https://github.com/signalwire/signalwire-go.git         sdks/signalwire-go \
    && git clone --depth 1 https://github.com/signalwire/signalwire-ruby.git       sdks/signalwire-ruby \
    && git clone --depth 1 https://github.com/signalwire/signalwire-perl.git       sdks/signalwire-perl \
    && git clone --depth 1 https://github.com/signalwire/signalwire-java.git       sdks/signalwire-java \
    && git clone --depth 1 https://github.com/signalwire/signalwire-cpp.git        sdks/signalwire-cpp \
    && git clone --depth 1 https://github.com/signalwire/signalwire-dotnet.git     sdks/signalwire-dotnet \
    && git clone --depth 1 https://github.com/signalwire/signalwire-php.git        sdks/signalwire-php

# ── Build all SDKs + wire up every language ─────────────────────────────────

# Python: venv + editable install
RUN python3 -m venv python/venv \
    && . python/venv/bin/activate \
    && pip install -q -r python/requirements.txt \
    && pip install -q -e sdks/signalwire-python

# TypeScript: build SDK + install workshop deps
RUN cd sdks/signalwire-typescript && npm install --silent && npm run build --silent \
    && cd /home/devuser/workshop/typescript && npm install --silent

# Go: tidy modules
RUN cd go && go mod tidy 2>/dev/null

# Ruby: bundle install
RUN cd ruby && bundle config set --local path vendor/bundle 2>/dev/null && bundle install --quiet

# Perl: install deps + symlink
RUN mkdir -p sdks/signalwire-perl/local \
    ; cpanm --quiet --notest --local-lib /home/devuser/workshop/sdks/signalwire-perl/local \
        --installdeps /home/devuser/workshop/sdks/signalwire-perl 2>/dev/null ; true
RUN rm -rf /home/devuser/workshop/perl/lib \
    && ln -sfn ../sdks/signalwire-perl/lib /home/devuser/workshop/perl/lib

# Java: build SDK jar + copy + set up gradle wrapper
ENV WS=/home/devuser/workshop
USER root
RUN cd ${WS}/sdks/signalwire-java && chmod +x gradlew && ./gradlew jar --console=plain -q
RUN mkdir -p ${WS}/java/libs \
    && cp ${WS}/sdks/signalwire-java/build/libs/signalwire-*.jar ${WS}/java/libs/ \
    && if [ ! -f ${WS}/java/gradlew ]; then \
         cp ${WS}/sdks/signalwire-java/gradlew ${WS}/java/gradlew && chmod +x ${WS}/java/gradlew \
         && mkdir -p ${WS}/java/gradle/wrapper \
         && cp ${WS}/sdks/signalwire-java/gradle/wrapper/* ${WS}/java/gradle/wrapper/; \
       fi \
    && chown -R devuser:devuser ${WS}/java
USER devuser

# C++: build static library
RUN cd sdks/signalwire-cpp && mkdir -p build \
    && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -3 && make -j$(nproc) 2>&1 | tail -3

# .NET: build SDK (net8.0 only)
RUN cd sdks/signalwire-dotnet \
    && dotnet build src/SignalWire/SignalWire.csproj -c Release -p:TargetFrameworks=net8.0 --nologo -v q

# PHP: install dependencies
RUN cd sdks/signalwire-php && composer install --quiet --no-interaction

# ── Help command + welcome message ──────────────────────────────────────────
RUN cat >> $HOME/.bashrc << 'BASHRC'

# ── Workshop help ──
help() {
    cat << 'HELPEOF'

  ╔══════════════════════════════════════════════════════════════╗
  ║  SignalWire AI Phone Agent Workshop                         ║
  ╚══════════════════════════════════════════════════════════════╝

  FIRST TIME? Run setup to enter your API credentials:

    ./setup.sh python          # set up one language
    ./setup.sh python go       # or several
    ./setup.sh                 # or all nine

  Setup will ask for your SignalWire, ngrok, and API keys, then
  configure ngrok and start the tunnel automatically.

  ─── Run an agent ─────────────────────────────────────────────

    Python:     cd python && source venv/bin/activate && python steps/step04_hello_agent.py
    TypeScript: cd typescript && npx tsx steps/step04_hello_agent.ts
    Go:         cd go && go run ./steps/step04_hello_agent
    Ruby:       cd ruby && bundle exec ruby steps/step04_hello_agent.rb
    Perl:       cd perl && PERL5LIB=../sdks/signalwire-perl/local/lib/perl5 perl steps/step04_hello_agent.pl
    Java:       cd java && source env.sh && cp steps/Step04HelloAgent.java src/main/java/HelloAgent.java && ./gradlew run -PmainClass=HelloAgent --console=plain
    C++:        cd cpp && cp steps/step04_hello_agent.cpp agent.cpp && cd build && cmake .. && make && ./agent

  ─── ngrok tunnel ─────────────────────────────────────────────

    View tunnel:   screen -r workshop-ngrok   (detach: Ctrl-A D)
    Stop tunnel:   screen -S workshop-ngrok -X quit
    Tunnel UI:     http://localhost:4040 (in your browser)

  ─── Workshop steps ───────────────────────────────────────────

    Step 04: Hello World agent        Step 08: Weather (DataMap)
    Step 06: Hardcoded jokes           Step 09: Polish & personality
    Step 07: Live API jokes            Step 10: Skills (datetime, math)
                                       Step 11: Complete agent

  ─── Useful commands ──────────────────────────────────────────

    ./setup.sh python          Re-run setup for a language
    cat .env                   View your credentials
    nano .env                  Edit your credentials
    help                       Show this message again

HELPEOF
}

# Show welcome on login
echo ""
echo "  Welcome to the SignalWire Workshop! Type 'help' to get started."
echo ""
BASHRC

EXPOSE 3000 4040

CMD ["bash", "-l"]
