
#!/bin/bash
echo "====================================================================================
AARCH64 BUILD NGINX WITH HTTP3 BY ANDY CUNGKRINX
===================================================================================="
echo "====================================================================================
Install Dependency Requirment
===================================================================================="
add-apt-repository ppa:ubuntu-toolchain-r/test
apt update
apt install -y libpcre3 libpcre3-dev zlib1g-dev cmake make automake golang g++-8 gcc-8 clang libunwind-dev golang
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 800 --slave /usr/bin/g++ g++ /usr/bin/g++-8

update-alternatives --config gcc
cd ~/
mkdir development


echo "====================================================================================
Build Openssl TLS 1.3
===================================================================================="
cd ~/development
git clone --depth 1 -b openssl-quic-draft-23 https://github.com/tatsuhiro-t/openssl
cd openssl
./config enable-tls1_3 --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib
make -j4 EXTRA_CMAKE_OPTIONS='-DCMAKE_C_COMPILER=arm64-linux-gcc -DCMAKE_CXX_COMPILER=arm64-linux-gnu-g++ -DCXX_STANDARD_REQUIRED=c++17'
make -j4 EXTRA_CMAKE_OPTIONS='-DCMAKE_C_COMPILER=arm64-linux-gcc -DCMAKE_CXX_COMPILER=arm64-linux-gnu-g++ -DCXX_STANDARD_REQUIRED=c++17' install_sw
rm -rf /usr/sbin/openssl
ls -s /usr/local/ssl/sbin/openssl /usr/sbin/


echo "====================================================================================
Build quiche
===================================================================================="
cd ~/development
git clone --recursive https://github.com/cloudflare/quiche

echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Boringssl build
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
cd ~/development/quiche/deps/
rm -rf boringssl
git clone https://github.com/raihan001/boringssl.git
cd boringssl
git checkout ARM64
mkdir build
cd build
cmake EXTRA_CMAKE_OPTIONS='-DCMAKE_C_COMPILER=arm64-linux-gcc -DCMAKE_CXX_COMPILER=arm64-linux-gnu-g++ -DCXX_STANDARD_REQUIRED=c++17 -DCMAKE_POSITION_INDEPENDENT_CODE=on' ..
make -j4 EXTRA_CMAKE_OPTIONS='-DCMAKE_C_COMPILER=arm64-linux-gcc -DCMAKE_CXX_COMPILER=arm64-linux-gnu-g++ -DCXX_STANDARD_REQUIRED=c++17'


echo "====================================================================================
Nginx http/3
===================================================================================="
cd ~/development

curl -O https://nginx.org/download/nginx-1.16.1.tar.gz
tar -xzvf nginx-1.16.1.tar.gz
cd nginx-1.16.1

echo "+++++++++++++++++++++++++++++++++++++
rustc installation
+++++++++++++++++++++++++++++++++++++"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env


patch -p01 < ../quiche/extras/nginx/nginx-1.16.patch
./configure \
--with-stream \
--with-threads \
--prefix=/usr/local/nginx \
--build="Nginx-Enabled-Http/3" \
--with-http_ssl_module \
--with-http_v2_module \
--with-http_v3_module \
--with-openssl=../quiche/deps/boringssl \
--with-quiche=../quiche

make -j4 EXTRA_CMAKE_OPTIONS='-DCMAKE_C_COMPILER=arm64-linux-gcc -DCMAKE_CXX_COMPILER=arm64-linux-gnu-g++ -DCXX_STANDARD_REQUIRED=c++17'
make -j4 EXTRA_CMAKE_OPTIONS='-DCMAKE_C_COMPILER=arm64-linux-gcc -DCMAKE_CXX_COMPILER=arm64-linux-gnu-g++ -DCXX_STANDARD_REQUIRED=c++17' install 
adduser --system --shell /bin/false --no-create-home --disabled-login --disabled-password --gecos "nginx user" --group nginx


echo "+++++++++++++++++++++++++++++++++++++++++++
enable systemd nginx
+++++++++++++++++++++++++++++++++++++++++++"
cat >/lib/systemd/system/nginx.service <<EOL
[Unit]
Description=Nginx - With Boringssl and http3
Documentation=https://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx.conf
ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID

[Install]
WantedBy=multi-user.target
EOL

echo "++++++++++++++++++++++++++++++++++++++++++++
copy directory
++++++++++++++++++++++++++++++++++++++++++++"
rm -rf /etc/nginx
rm -rf /usr/sbin/nginx
ls -s /usr/local/nginx/sbin/nginx /usr/sbin/
cp /usr/local/nginx/conf /etc/nginx
mkdir /etc/nginx/certs
mkdir /etc/nginx/conf.d
mkdir /etc/nginx/sites-enabled
mkdir /etc/nginx/sites-available
mkdir /var/log/nginx


echo "+++++++++++++++++++++++++++++++++++++++++++
Create default nginx configuration
+++++++++++++++++++++++++++++++++++++++++++"
cat >/etc/nginx/sites-available/default <<EOL
server {
       listen 80 default_server;
       listen [::]:80 default_server;

       server_name _;

       root /var/www/html;
       index.php index.html index.htm index.nginx-debian.html;

       location / {
               try_files $uri $uri/ =404;
       }
}
EOL

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/certs/private.key -out /etc/nginx/certs/cert.crt


cat >/etc/nginx/sites-available/default-http3 <<EOL
server {
        # Enable QUIC and HTTP/3.
        listen 443 quic reuseport;

        # Enable HTTP/2 (optional).
        listen 443 ssl http2;
	
        ssl_certificate      /etc/nginx/certs/cert.crt;
        ssl_certificate_key  /etc/nginx/certs/private.key;

        # Enable all TLS versions (TLSv1.3 is required for QUIC).
        ssl_protocols TLSv1.2 TLSv1.3;

        # Add Alt-Svc header to negotiate HTTP/3.
        add_header alt-svc 'h3-23=":443"; ma=86400';
}
EOL
ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
ln -s /etc/nginx/sites-available/default-http3 /etc/nginx/sites-enabled/


cat >/etc/nginx/conf.d/proxy.conf <<EOL
proxy_redirect          off;
proxy_set_header        Host            $host;
proxy_set_header        X-Real-IP       $remote_addr;
proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
client_max_body_size    10m;
client_body_buffer_size 128k;
proxy_connect_timeout   90;
proxy_send_timeout      90;
proxy_read_timeout      90;
proxy_buffers           32 4k;
EOF

user       www-data;  
worker_processes  auto;  
error_log  /var/log/nginx/error.log crit;
pid        /var/run/nginx.pid;
worker_rlimit_nofile 8192;
EOL

cat >/etc/nginx/nginx.conf <<EOL
events {
  worker_connections  4096;
}

http {
  include    /etc/nginx/mime.types;
  include    /etc/nginx/conf.d/proxy.conf;
  include    /etc/nginx/fastcgi.conf;
  include    /etc/nginx/sites-enabled/*;

  default_type application/octet-stream;
  access_log   logs/access.log  main;
  sendfile     on;
  tcp_nopush   on;
  server_names_hash_bucket_size 128;
}
EOL

systemctl daemon-reload


echo "====================================================================================
ALL DONE!!!
===================================================================================="

echo "+++++++++++++++++++++++++++++++++++++++++++
You can run with this command
+++++++++++++++++++++++++++++++++++++++++++

systemctl start nginx
systemctl status nginx

+++++++++++++++++++++++++++++++++++++++++++
Then check your browser
+++++++++++++++++++++++++++++++++++++++++++
http://localhost
https://localhost"

exit;


