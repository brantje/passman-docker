#!/usr/bin/env bash
#set -xo pipefail
# Nextcloud
##########################

export DB_NAME=nextcloud
export DB_USER=nextcloud
export DB_HOST=localhost
export DB_TYPE=mysql
export DB_PASSWORD="$(date +%s | sha256sum | base64 | head -c 32 ; echo)"
DATA_DIR="$(mysqld --verbose --help --log-bin-index=`mktemp -u` 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"

echo "Data dir: $DATA_DIR"

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
  mysql_install_db --user=mysql --datadir="$DATA_DIR" --rpm  &> /dev/null
  echo 'Database initialized'

  mysqld_safe --pid-file=$PID_FILE --skip-networking --nowatch  &> /dev/null

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
    echo "Nextcloud DB: $DB_NAME"
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


sed -i -e "s/<UPLOAD_MAX_SIZE>/$UPLOAD_MAX_SIZE/g" /etc/nginx/nginx.conf /etc/php7/php-fpm.conf \
       -e "s/<APC_SHM_SIZE>/$APC_SHM_SIZE/g" /etc/php7/conf.d/apcu.ini \
       -e "s/<OPCACHE_MEM_SIZE>/$OPCACHE_MEM_SIZE/g" /etc/php7/conf.d/00_opcache.ini \
       -e "s/<REDIS_MAX_MEMORY>/$REDIS_MAX_MEMORY/g" /etc/redis.conf \
       -e "s/<CRON_PERIOD>/$CRON_PERIOD/g" /etc/s6.d/cron/run


# Put the configuration and apps into volumes
ln -sf /config/config.php /nextcloud/config/config.php &>/dev/null


chown -R $UID:$GID /nextcloud /data /config /etc/nginx /etc/php7 /var/log /var/lib/nginx /var/lib/redis /tmp /etc/s6.d


exec su-exec $UID:$GID /usr/local/bin/startup/redis/run &

openssl dhparam -dsaparam -out /etc/ssl/dhparam.pem 4096

CONFIGFILE=/config/config.php



# Create an initial configuration file.
instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
cat > $CONFIGFILE <<EOF;
<?php
\$CONFIG = array (
  'datadirectory' => '/data',
  'integrity.check.disabled' => true,
  "apps_paths" => array (
      0 => array (
              "path"     => "/nextcloud/apps",
              "url"      => "/apps",
              "writable" => true,
      ),
  ),

  'memcache.local' => '\OC\Memcache\APCu',

  'memcache.locking' => '\OC\Memcache\Redis',
   'redis' => array(
        'host' => '/tmp/redis.sock',
        'port' => 0,
        'timeout' => 0.0,
         ),

  'instanceid' => '$instanceid',
);
?>
EOF

# Create an auto-configuration file to fill in database settings
# when the install script is run. Make an administrator account
# here or else the install can't finish.
adminpassword=$(dd if=/dev/urandom bs=1 count=40 2>/dev/null | sha1sum | fold -w 30 | head -n 1)
cat > /nextcloud/config/autoconfig.php <<EOF;
<?php
\$AUTOCONFIG = array (
  # storage/database
  'directory'     => '/data',
  'dbtype'        => '${DB_TYPE:-sqlite3}',
  'dbname'        => '${DB_NAME:-nextcloud}',
  'dbuser'        => '${DB_USER:-nextcloud}',
  'dbpass'        => '${DB_PASSWORD:-password}',
  'dbhost'        => '${DB_HOST:-nextcloud-db}',
  'dbtableprefix' => 'oc_',
EOF
if [[ ! -z "$ADMIN_USER"  ]]; then
  cat >> /nextcloud/config/autoconfig.php <<EOF;
  # create an administrator account with a random password so that
  # the user does not have to enter anything on first load of ownCloud
  'adminlogin'    => '${ADMIN_USER}',
  'adminpass'     => '${ADMIN_PASSWORD}',
EOF
fi
cat >> /nextcloud/config/autoconfig.php <<EOF;
);
?>
EOF

echo "Starting automatic configuration..."
# Execute ownCloud's setup step, which creates the ownCloud database.
# It also wipes it if it exists. And it updates config.php with database
# settings and deletes the autoconfig.php file.
(cd /nextcloud; php7 index.php)
echo "Automatic configuration finished."

# Update config.php.
# * trusted_domains is reset to localhost by autoconfig starting with ownCloud 8.1.1,
#   so set it here. It also can change if the box's PRIMARY_HOSTNAME changes, so
#   this will make sure it has the right value.
# * Some settings weren't included in previous versions of Mail-in-a-Box.
# * We need to set the timezone to the system timezone to allow fail2ban to ban
#   users within the proper timeframe
# * We need to set the logdateformat to something that will work correctly with fail2ban
# Use PHP to read the settings file, modify it, and write out the new settings array.

CONFIG_TEMP=$(/bin/mktemp)
php7 <<EOF > $CONFIG_TEMP && mv $CONFIG_TEMP $CONFIGFILE
<?php
include("/config/config.php");

//\$CONFIG['memcache.local'] = '\\OC\\Memcache\\Memcached';
\$CONFIG['mail_from_address'] = 'administrator'; # just the local part, matches our master administrator address

\$CONFIG['logtimezone'] = '$TZ';
\$CONFIG['logdateformat'] = 'Y-m-d H:i:s';

echo "<?php\n\\\$CONFIG = ";
var_export(\$CONFIG);
echo ";";
?>
EOF

chown -R $UID:$GID /config
# Enable/disable apps. Note that this must be done after the ownCloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows ownCloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
occ app:disable firstrunwizard

declare -a apps=( "passman" "notifications")
for i in "${apps[@]}"
do
    echo "Installing $i"
    wget -q "https://github.com/nextcloud/$i/archive/master.zip"
    unzip -q master.zip -d /nextcloud/apps
    rm master.zip
    mv "/nextcloud/apps/$i-master" "/nextcloud/apps/$i"
    occ app:enable $i
done

echo '' > /data/nextcloud.log
