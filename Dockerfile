FROM alpine:3.12
MAINTAINER Ian Duffy <ian@ianduffy.ie>

ENV POWERDNS_VERSION=4.3.0

RUN apk --update add bash libpq sqlite-libs libstdc++ libgcc mariadb-client mariadb-connector-c lua-dev curl-dev && \
    apk add --virtual build-deps \
      g++ make mariadb-dev postgresql-dev sqlite-dev curl boost-dev mariadb-connector-c-dev && \
    curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
    cd /tmp/pdns-$POWERDNS_VERSION && \
    ./configure --prefix="" --exec-prefix=/usr --sysconfdir=/etc/pdns \
      --with-modules="bind gmysql gpgsql gsqlite3" && \
    make && make install-strip && cd / && \
    mkdir -p /etc/pdns/conf.d && \
    addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null && \
    cp /usr/lib/libboost_program_options* /tmp && \
    apk del --purge build-deps && \
    mv /tmp/lib* /usr/lib/ && \
    rm -rf /tmp/pdns-$POWERDNS_VERSION /var/cache/apk/*

COPY schema.sql pdns.conf /etc/pdns/
COPY entrypoint.sh /

EXPOSE 53/tcp 53/udp
EXPOSE 8081/tcp

ENV REFRESHED_AT="2020-07-1" \
    MYSQL_DEFAULT_AUTOCONF=true \
    MYSQL_DEFAULT_HOST="mysql" \
    MYSQL_DEFAULT_PORT="3306" \
    MYSQL_DEFAULT_USER="root" \
    MYSQL_DEFAULT_PASS="root" \
    MYSQL_DEFAULT_DB="pdns" \
    WEBSERVER_DEFAULT_ENABLED=true \
    WEBSERVER_DEFAULT_BIND_ADDRESS=0.0.0.0 \
    WEBSERVER_DEFAULT_PORT=8081 \
    WEBSERVER_DEFAULT_ALLOW_FROM="0.0.0.0/0,::/0" \
    API_DEFAULT_ENABLED=true \
    API_DEFAULT_KEY="changeme"

ENTRYPOINT ["/entrypoint.sh"]
