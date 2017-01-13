#!/bin/sh

sed -i -e "s/<UPLOAD_MAX_SIZE>/$UPLOAD_MAX_SIZE/g" /etc/nginx/nginx.conf /etc/php7/php-fpm.conf \
       -e "s/<APC_SHM_SIZE>/$APC_SHM_SIZE/g" /etc/php7/conf.d/apcu.ini \
       -e "s/<OPCACHE_MEM_SIZE>/$OPCACHE_MEM_SIZE/g" /etc/php7/conf.d/00_opcache.ini \
       -e "s/<REDIS_MAX_MEMORY>/$REDIS_MAX_MEMORY/g" /etc/redis.conf \
       -e "s/<CRON_PERIOD>/$CRON_PERIOD/g" /etc/s6.d/cron/run

# Put the configuration and apps into volumes
ln -sf /config/config.php /nextcloud/config/config.php &>/dev/null
ln -sf /apps2 /nextcloud &>/dev/null

chown -R $UID:$GID /nextcloud /data /config /apps2 /etc/nginx /etc/php7 /var/log /var/lib/nginx /var/lib/redis /tmp /etc/s6.d

exec su-exec $UID:$GID /usr/local/bin/startup/redis/run &
if [ ! -f /config/config.php ]; then
    export DB_NAME=nextcloud
    export DB_USER=nextcloud
    export DB_PASSWORD="$(date +%s | sha256sum | base64 | head -c 32 ; echo)"
    export DB_HOST=localhost
    export DB_TYPE=mysql
    # New installation, run the setup
    /usr/local/bin/setup_mysql.sh
    /usr/local/bin/setup.sh
else
    occ upgrade
    if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
        echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
        occ upgrade
        if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
        occ maintenance:mode --off
        echo "...which seemed to work."
    fi
fi

chown -R $UID:$GID /nextcloud /data /config /apps2 /etc/nginx /etc/php7 /var/log /var/lib/nginx /tmp /etc/s6.d

exec su-exec $UID:$GID /bin/s6-svscan /etc/s6.d
