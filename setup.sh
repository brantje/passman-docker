#!/usr/bin/env bash
# Nextcloud
##########################

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

openssl dhparam -dsaparam -out /etc/ssl/dhparam.pem 4096

CONFIGFILE=/config/config.php



# Create an initial configuration file.
instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
cat > $CONFIGFILE <<EOF;
<?php
\$CONFIG = array (
  'datadirectory' => '/data',

  "apps_paths" => array (
      0 => array (
              "path"     => "/nextcloud/apps",
              "url"      => "/apps",
              "writable" => false,
      ),
      1 => array (
              "path"     => "/apps2",
              "url"      => "/apps2",
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
occ config:system:set defaultapp --value=passman
occ config:system:set trusted_domains 2 --value=172.17.0.2
occ config:system:set trusted_domains 3 --value=$HOSTNAME
echo '' > /data/nextcloud.log

