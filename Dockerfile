FROM alpine:3.12 AS compiler
MAINTAINER Ian Duffy <ian@ianduffy.ie>

ENV POWERDNS_VERSION=4.3.0

RUN apk --update add bash libpq sqlite-libs libstdc++ libgcc mariadb-client mariadb-connector-c lua-dev curl-dev && \
    apk add --virtual build-deps \
      g++ make mariadb-dev postgresql-dev sqlite-dev curl boost-dev mariadb-connector-c-dev && \
    curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
    cd /tmp/pdns-$POWERDNS_VERSION && \
    ./configure --prefix="/opt/pdns" \
      --with-modules="bind gmysql gpgsql gsqlite3" && \
    make && make install-strip

FROM alpine:3.12
MAINTAINER Ian Duffy <ian@ianduffy.ie>

RUN apk --update add bash mariadb-connector-c lua-libs libpq sqlite-libs libcurl mariadb-client && \
    addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null && \
    rm -rf /var/cache/apk/*

COPY --from=compiler /opt /opt
COPY --from=compiler /usr/lib/libboost_program_options* /usr/lib/

COPY schema.sql pdns.conf /opt/pdns/etc/
COPY entrypoint.sh /

RUN mkdir -p /opt/pdns/etc/conf.d

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

ENV PATH="/opt/pdns/bin:/opt/pdns/sbin:${PATH}"

ENTRYPOINT ["/entrypoint.sh"]
