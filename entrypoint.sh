#!/bin/bash
set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
# source: https://github.com/docker-library/mariadb/blob/master/docker-entrypoint.sh
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        echo "Both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

# Loads various settings that are used elsewhere in the script
docker_setup_env() {
    # Initialize values that might be stored in a file

    file_env 'MYSQL_AUTOCONF' $MYSQL_DEFAULT_AUTOCONF
    file_env 'MYSQL_HOST' $MYSQL_DEFAULT_HOST
    file_env 'MYSQL_DNSSEC' 'no'
    file_env 'MYSQL_DB' $MYSQL_DEFAULT_DB
    file_env 'MYSQL_PASS' $MYSQL_DEFAULT_PASS
    file_env 'MYSQL_USER' $MYSQL_DEFAULT_USER
    file_env 'MYSQL_PORT' $MYSQL_DEFAULT_PORT
    file_env 'WEBSERVER_ENABLED' $WEBSERVER_DEFAULT_ENABLED
    file_env 'WEBSERVER_BIND_ADDRESS' $WEBSERVER_DEFAULT_BIND_ADDRESS
    file_env 'WEBSERVER_PORT' $WEBSERVER_DEFAULT_PORT
    file_env 'WEBSERVER_ALLOW_FROM' $WEBSERVER_DEFAULT_ALLOW_FROM
    file_env 'API_ENABLED' $API_DEFAULT_ENABLED
    file_env 'API_KEY' $API_DEFAULT_KEY
}

docker_setup_env

# --help, --version
[ "$1" = "--help" ] || [ "$1" = "--version" ] && exec pdns_server $1
# treat everything except -- as exec cmd
[ "${1:0:2}" != "--" ] && exec "$@"

if $MYSQL_AUTOCONF ; then
  # Set MySQL Credentials in pdns.conf
  sed -r -i "s/^[# ]*gmysql-host=.*/gmysql-host=${MYSQL_HOST}/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*gmysql-port=.*/gmysql-port=${MYSQL_PORT}/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*gmysql-user=.*/gmysql-user=${MYSQL_USER}/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*gmysql-password=.*/gmysql-password=${MYSQL_PASS}/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*gmysql-dbname=.*/gmysql-dbname=${MYSQL_DB}/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*gmysql-dnssec=.*/gmysql-dnssec=${MYSQL_DNSSEC}/g" /opt/pdns/etc/pdns.conf

  MYSQLCMD="mysql --host=${MYSQL_HOST} --user=${MYSQL_USER} --password=${MYSQL_PASS} --port=${MYSQL_PORT} -r -N"

  # wait for Database come ready
  isDBup () {
    echo "SHOW STATUS" | $MYSQLCMD 1>/dev/null
    echo $?
  }

  RETRY=10
  until [ `isDBup` -eq 0 ] || [ $RETRY -le 0 ] ; do
    echo "Waiting for database to come up"
    sleep 5
    RETRY=$(expr $RETRY - 1)
  done
  if [ $RETRY -le 0 ]; then
    >&2 echo Error: Could not connect to Database on $MYSQL_HOST:$MYSQL_PORT
    exit 1
  fi

  # init database if necessary
  echo "CREATE DATABASE IF NOT EXISTS $MYSQL_DB;" | $MYSQLCMD
  MYSQLCMD="$MYSQLCMD $MYSQL_DB"

  if [ "$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"$MYSQL_DB\";" | $MYSQLCMD)" -le 1 ]; then
    echo Initializing Database
    cat /opt/pdns/etc/schema.sql | $MYSQLCMD

    # Run custom mysql post-init sql scripts
    if [ -d "/opt/pdns/etc/mysql-postinit" ]; then
      for SQLFILE in $(ls -1 /opt/pdns/etc/mysql-postinit/*.sql | sort) ; do
        echo Source $SQLFILE
        cat $SQLFILE | $MYSQLCMD
      done
    fi
  fi

  unset -v MYSQL_PASS
fi

if $WEBSERVER_ENABLED ; then
  sed -r -i "s/^[# ]*webserver=.*/webserver=yes/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*webserver-address=.*/webserver-address=${WEBSERVER_BIND_ADDRESS}/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*webserver-port=.*/webserver-port=${WEBSERVER_PORT}/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s|^[# ]*webserver-allow-from=.*|webserver-allow-from=${WEBSERVER_ALLOW_FROM}|g" /opt/pdns/etc/pdns.conf


  if [ -z ${WEBSERVER_PASSWORD+x} ] ; then
    sed -r -i "s/^[# ]*webserver-password=.*/webserver-password=${WEBSERVER_PASSWORD}/g" /opt/pdns/etc/pdns.conf
  fi
fi

if $API_ENABLED ; then
  sed -r -i "s/^[# ]*api=.*/api=yes/g" /opt/pdns/etc/pdns.conf
  sed -r -i "s/^[# ]*api-key=.*/api-key=${API_KEY}/g" /opt/pdns/etc/pdns.conf
fi

# Run pdns server
trap "pdns_control quit" SIGHUP SIGINT SIGTERM

pdns_server "$@" &

wait
