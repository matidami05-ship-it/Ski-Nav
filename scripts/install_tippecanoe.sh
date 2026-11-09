#!/usr/bin/env bash
# Installs tippecanoe from source (the distro package can be too old to write .pmtiles).
set -euo pipefail
command -v tippecanoe >/dev/null && tippecanoe --version 2>&1 | head -1 && exit 0
sudo apt-get install -y -q build-essential libsqlite3-dev zlib1g-dev
git clone -q --depth 1 https://github.com/felt/tippecanoe /tmp/tippecanoe
make -C /tmp/tippecanoe -j"$(nproc)" >/dev/null
sudo make -C /tmp/tippecanoe install >/dev/null
tippecanoe --version 2>&1 | head -1
