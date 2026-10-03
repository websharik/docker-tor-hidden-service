FROM    python:3.10-alpine

# If omitted or empty, use the versions recorded in the repository.
ARG     tor_version
ARG     torsocks_version

ENV     HOME=/var/lib/tor
ENV     POETRY_VIRTUALENVS_CREATE=false

COPY    current_tor_version current_torsocks_version /usr/local/src/

RUN     apk add --no-cache git bind-tools cargo libevent-dev openssl-dev gnupg gcc make automake ca-certificates autoconf musl-dev coreutils libffi-dev zlib-dev && \
    mkdir -p /usr/local/src/ /var/lib/tor/ && \
    git clone https://git.torproject.org/tor.git /usr/local/src/tor && \
    cd /usr/local/src/tor && \
    TOR_VERSION=${tor_version:-$(tr -d '[:space:]' < /usr/local/src/current_tor_version)} && \
    git checkout "tor-$TOR_VERSION" && \
    ./autogen.sh && \
    ./configure \
    --disable-asciidoc \
    --sysconfdir=/etc \
    --disable-unittests && \
    make -j"$(nproc)" && make install && \
    cd .. && \
    rm -rf tor && \
    pip3 install --no-cache-dir 'poetry==1.8.5' && \
    apk del git libevent-dev openssl-dev gnupg cargo make automake autoconf musl-dev coreutils libffi-dev && \
    apk add --no-cache libevent openssl

RUN    apk add --no-cache git gcc make automake autoconf musl-dev libtool && \
    git clone https://git.torproject.org/torsocks.git /usr/local/src/torsocks && \
    cd /usr/local/src/torsocks && \
    TORSOCKS_VERSION=${torsocks_version:-$(tr -d '[:space:]' < /usr/local/src/current_torsocks_version)} && \
    git checkout "$TORSOCKS_VERSION" && \
    ./autogen.sh && \
    ./configure && \
    make && make install && \
    cd .. && \
    rm -rf torsocks && \
    apk del git gcc make automake autoconf musl-dev libtool

RUN     mkdir -p /etc/tor/

COPY    pyproject.toml poetry.lock /usr/local/src/onions/

# PyYAML 6.0 in the lock file requires Cython 0.x when built from source on Alpine.
RUN     cd /usr/local/src/onions && apk add --no-cache openssl-dev libffi-dev gcc libc-dev && \
    printf 'Cython<3\n' > /tmp/build-constraints.txt && \
    PIP_CONSTRAINT=/tmp/build-constraints.txt pip3 install --no-cache-dir --use-pep517 'PyYAML==6.0' && \
    poetry install --only main --no-root --no-interaction && \
    rm /tmp/build-constraints.txt && \
    apk del libffi-dev gcc libc-dev openssl-dev

COPY    onions /usr/local/src/onions/onions
RUN     cd /usr/local/src/onions && apk add --no-cache gcc libc-dev && \
    poetry install --only main --no-interaction && \
    apk del gcc libc-dev

RUN     mkdir -p ${HOME}/.tor && \
    addgroup -S -g 107 tor && \
    adduser -S -G tor -u 104 -H -h ${HOME} tor

COPY    assets/entrypoint-config.yml /
COPY    assets/torrc /var/local/tor/torrc.tpl
COPY    assets/vanguards.conf.tpl /var/local/tor/vanguards.conf.tpl

ENV     VANGUARDS_CONFIG=/etc/tor/vanguards.conf

VOLUME  ["/var/lib/tor/hidden_service/"]

ENTRYPOINT ["pyentrypoint"]

CMD     ["tor"]
