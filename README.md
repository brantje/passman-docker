![](https://s32.postimg.org/69nev7aol/Nextcloud_logo.png)

### Features
- Based on Alpine Linux Edge.
- Bundled with nginx and PHP 7.
- Automatic installation using environment variables.
- Package integrity and authenticity checked during building process.
- Data and apps persistence.
- OPCache (opcocde), APCu (local), Redis (file locking) installed and configured.
- system cron task running.
- Using maria DB
- Redis, FTP, SMB, LDAP support.
- GNU Libiconv for php iconv extension (avoiding errors with some apps).
- No root processes. Never.
- Environment variables provided (see below).
- Diffie hellman key generated on container creation
   

### Tags
- **latest** : latest stable version.
- **11.0** : latest 11.0.x version (stable)
- **daily** : latest code (daily build).

Other tags than `daily` are built weekly. For security reasons, you should occasionally update the container, even if you have the latest version of Nextcloud.

### Build-time variables
- **NEXTCLOUD_VERSION** : version of nextcloud
- **GNU_LIBICONV_VERSION** : version of GNU Libiconv
- **GPG_nextcloud** : signing key fingerprint

### Environment variables
- **UID** : nextcloud user id *(default : 991)*
- **GID** : nextcloud group id *(default : 991)*
- **UPLOAD_MAX_SIZE** : maximum upload size *(default : 10G)*
- **APC_SHM_SIZE** : apc memory size *(default : 128M)*
- **OPCACHE_MEM_SIZE** : opcache memory size in megabytes *(default : 128)*
- **REDIS_MAX_MEMORY** : memory limit for Redis *(default : 64mb)*
- **CRON_PERIOD** : time interval between two cron tasks *(default : 15m)*
- **TZ** : the system/log timezone *(default : Etc/UTC)*
- **ADMIN_USER** : username of the admin account *(default : admin)*
- **ADMIN_PASSWORD** : password of the admin account *(default : admin)*
- **DB_TYPE** : database type (sqlite3, mysql or pgsql) *(default : mysql)*
- **DB_NAME** : name of database *(default : nextcloud)*
- **DB_USER** : username for database *(default : nextcloud)*
- **DB_PASSWORD** : password for database user *(default : random generated)*
- **DB_HOST** : database host *(default : localhost)*
- **HOSTNAME**: Hostname of the instance


Don't forget to use a **strong password** for the admin account!

### Ports
- **8888** : HTTP Nextcloud port.
- **8443** : HTTPS Nextcloud port.

### Volumes
- **/data** : Nextcloud data.
- **/config** : config.php location.
- **/apps2** : Nextcloud downloaded apps.
- **/var/lib/redis** : Redis dumpfile location.
- **/var/lib/mysql**: Mysql database location.  
- **/ssl**: Here we look for `fullchain.pem` and `privkey.pem`, if not found they are generated.


### Setup
Pull the image and create a container. `/mnt` can be anywhere on your host, this is just an example.

```
docker pull brantje/passman-docker:10.0
       
docker run -d --name nextcloud \
       -v /mnt/nextcloud/data:/data \
       -v /mnt/nextcloud/config:/config \
       -v /mnt/nextcloud/apps:/apps2 \
       -v /mnt/nextcloud/db:/var/lib/mysql \
       -e UID=1000 -e GID=1000 \
       -e UPLOAD_MAX_SIZE=10G \
       -e APC_SHM_SIZE=128M \
       -e OPCACHE_MEM_SIZE=128 \
       -e REDIS_MAX_MEMORY=64mb \
       -e CRON_PERIOD=15m \
       -e TZ=Etc/UTC \
       -e ADMIN_USER=mrrobot \
       -e ADMIN_PASSWORD=supercomplicatedpassword \
       -e DB_TYPE=mysql \
       -e DB_NAME=nextcloud \
       -e DB_USER=nextcloud \
       -e DB_PASSWORD=supersecretpassword \
       -e DB_HOST=db_nextcloud \
       brantje/passman-docker:10.0
```

**Below you can find a docker-compose file, which is very useful!**

Now you have to use a **reverse proxy** in order to access to your container through Internet, steps and details are available at the end of the README.md. And that's it! Since you already configured Nextcloud through setting environment variables, there's no setup page.

### ARM-based devices
This image is available for `armhf` (Raspberry Pi 1 & 2, Scaleway C1, ...). Although Docker does support ARM-based devices, Docker Hub only builds for x86_64. That's why you will have to build this image yourself! Don't panic, this is easy.

```
git clone https://github.com/brantje/passman-docker.git
cd 10.0-armhf
docker build -t brantje/passman .
```

The building process can take some time.

### Configure
In the admin panel, you should switch from `AJAX cron` to `cron` (system cron).

### Update
Pull a newer image, then recreate the container as you did before (*Setup* step). None of your data will be lost since you're using external volumes. If Nextcloud performed a full upgrade, your apps could be disabled, enable them again.


### Reverse proxy
Of course you can use your own solution to do so! nginx, Haproxy, Caddy, h2o, there's plenty of choices and documentation about it on the Web.

Personally I'm using nginx, so if you're using nginx, there are two possibilites :

- nginx is on the host : get the Nextcloud container IP address with `docker inspect nextcloud | grep IPAddress\" | head -n1 | grep -Eo "[0-9.]+" `. But whenever the container is restarted or recreated, its IP address can change. Or you can bind Nextcloud HTTP port (8888) to the host (so the reverse proxy can access with `http://localhost:8888` or whatever port you set), but in this case you should consider using a firewall since it's also listening to `http://0.0.0.0:8888`.

- nginx is in a container, things are easier : you can link nextcloud container to an nginx container so you can use `proxy_pass http://nextcloud:8888`. An example of configuration would be :

```
server {
  listen 8000;
  server_name example.com;
  return 301 https://$host$request_uri;
}

server {
  listen 4430 ssl http2;
  server_name example.com;

  ssl_certificate /certs/example.com.crt;
  ssl_certificate_key /certs/example.com.key;

  include /etc/nginx/conf/ssl_params.conf;

  client_max_body_size 10G; # change this value it according to $UPLOAD_MAX_SIZE

  location / {
    proxy_pass http://nextcloud:8888;
    include /etc/nginx/conf/proxy_params;
  }
}
```


Headers are already sent by the container, including HSTS, so there's no need to add them again. **It is strongly recommended to use Nextcloud through an encrypted connection (HTTPS).** [Let's Encrypt](https://letsencrypt.org/) provides free SSL/TLS certificates (trustworthy!).