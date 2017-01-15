#!/bin/sh
echo "Starting instance with hostname: $HOSTNAME"

#SSL Setup
if [[  -e /ssl/fullchain.pem || -e /ssl/privkey.pem ]]
    then
        echo "Using your ssl certs"
else
    echo "Generating certs for $HOSTNAME"
    openssl req -new -x509 -days 3650 -nodes \
                -out /ssl/fullchain.pem \
                -keyout /ssl/privkey.pem \
                -subj "/O=Nextcloud/OU=Passman/CN=$HOSTNAME"
fi


if [[ ${HOSTNAME} != *"demo.passman.cc"* ]];then
    # testmystring does not contain c0
    echo "This is a custom image buid for demo.passman.cc"
    echo "It's not recommend to use this in production!"
fi

exec  mysqld -u mysql > /dev/null 2>&1 &
sleep 5
echo "mysqld: ready for connections."

# Put the configuration and apps into volumes
ln -sf /config/config.php /nextcloud/config/config.php &>/dev/null



exec su-exec $UID:$GID /usr/local/bin/startup/redis/run &

chown -R $UID:$GID /nextcloud /data /config /etc/nginx /etc/php7 /var/log /var/lib/nginx /tmp /etc/s6.d

occ config:system:set defaultapp --value=passman
occ config:system:set trusted_domains 2 --value=172.17.0.2
occ config:system:set trusted_domains 3 --value=$HOSTNAME

exec su-exec $UID:$GID /bin/s6-svscan /etc/s6.d

