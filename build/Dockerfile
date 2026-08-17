FROM emscripten/emsdk:2.0.0

# Debian Buster is EOL; redirect to the archive mirror
RUN sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g; \
            s|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g; \
            /buster-updates/d' /etc/apt/sources.list

RUN apt-get update && apt-get install -y \
    cmake make git python3 pkg-config \
    --no-install-recommends && rm -rf /var/lib/apt/lists/*

WORKDIR /work
