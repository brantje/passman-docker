#!/bin/sh
#set -xo pipefail

DATA_DIR="$(mysqld --verbose --help --log-bin-index=`mktemp -u` 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"
PID_FILE=/run/mysqld/mysqld.pid
if [ ! -d "$DATA_DIR/mysql" ]; then
  if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
    echo >&2 'error: database is uninitialized and password option is not specified '
    echo >&2 'You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
    exit 1
  fi

  mkdir -p "$DATA_DIR"
  chown -R mysql:mysql "$DATA_DIR"

  echo 'Initializing database'
  mysql_install_db --user=mysql --datadir="$DATA_DIR" --rpm &> /dev/null
  echo 'Database initialized'

  mysqld_safe --pid-file=$PID_FILE --skip-networking --nowatch &> /dev/null

  mysql_options='--protocol=socket -uroot'

  for i in `seq 30 -1 0`; do
    if mysql $mysql_options -e 'SELECT 1' &> /dev/null; then
      break
    fi
    echo 'MySQL init process in progress...'
    sleep 1
  done
  if [ "$i" = 0 ]; then
    echo >&2 'MySQL init process failed.'
    exit 1
  fi

  if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
    echo "Setting  mysql timezone..."

    # sed is for https://bugs.mysql.com/bug.php?id=20545
    mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | mysql $mysql_options mysql
  fi

  if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
    MYSQL_ROOT_PASSWORD="$(date +%s | sha256sum | base64 | head -c 32 ; echo)"
    echo
    echo
    echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
  fi

  mysql $mysql_options <<-EOSQL
    -- What's done in this file shouldn't be replicated
    --  or products like mysql-fabric won't work
    SET @@SESSION.SQL_LOG_BIN=0;
    DELETE FROM mysql.user ;
    CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
    GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
    DROP DATABASE IF EXISTS test ;
    FLUSH PRIVILEGES ;
EOSQL

  if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
    mysql_options="$mysql_options -p${MYSQL_ROOT_PASSWORD}"
  fi

  if [ "$DB_NAME" ]; then
    mysql $mysql_options -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` ;"
    mysql_options="$mysql_options $DB_NAME"
  fi

  if [ "$DB_USER" -a "$DB_PASSWORD" ]; then
    mysql $mysql_options -e "CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD' ;"

    if [ "$DB_NAME" ]; then
      mysql $mysql_options -e "GRANT ALL ON \`$DB_NAME\`.* TO '$DB_USER'@'%' ;"
    fi

    mysql $mysql_options '-e FLUSH PRIVILEGES;'
    echo
    echo "Generated db info for nextcloud"
    echo "Nextcloud DB user: $DB_USER"
    echo "Nextcloud DB pass: $DB_PASSWORD"
  fi

  echo


  pid="`cat $PID_FILE`"
  if ! kill -s TERM "$pid"; then
    echo >&2 'MySQL init process failed.'
    exit 1
  fi

  # make sure mysql completely ended


  echo
  echo 'MySQL init process done. Ready for start up.'
  echo
fi
exec  mysqld -u mysql > /dev/null 2>&1 &
sleep 5
echo "mysqld: ready for connections."
#exec mysqld_safe --pid-file=$PID_FILE &