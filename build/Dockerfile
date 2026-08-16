FROM emscripten/emsdk:2.0.0

RUN apt-get update && apt-get install -y \
    cmake make git python3 pkg-config \
    --no-install-recommends && rm -rf /var/lib/apt/lists/*

WORKDIR /work
