#!/bin/bash -v
echo root:centos | chpasswd

setenforce 0
cat << REPO > /etc/yum.repos.d/local.repo
[local]
name=local
baseurl=http://192.168.10.9/repos/wordpress
enabled=1
gpgcheck=0
REPO
yum -y -q install httpd
yum -y install php php-gd php-mysql httpd wget tmux vim unzip

systemctl enable httpd.service
systemctl restart httpd.service
setsebool -P httpd_can_network_connect_db=1

# download wordpress
cd /root
wget http://wordpress.org/latest.tar.gz
rm /var/www/html/index.html
tar -xzf latest.tar.gz

#echo "db_user:$db_user/db_name:$db_name/db_password:$db_password" 
cp wordpress/wp-config-sample.php wordpress/wp-config.php

sed -i "/Deny from All/d" /httpd/conf.d/wordpress.conf
sed -i "s/Require local/Require all granted/" /httpd/conf.d/wordpress.conf
sed -i "s/AllowOverride Options/AllowOverride All/" /httpd/conf.d/wordpress.conf

sed -i "s/database_name_here/$db_name/" wordpress/wp-config.php
sed -i "s/username_here/$db_user/" wordpress/wp-config.php
sed -i "s/password_here/$db_password/" wordpress/wp-config.php
sed -i "s/localhost/$db_host/" wordpress/wp-config.php

cp -avR wordpress/* /var/www/html/

mkdir /var/www/html/wp-content/uploads

yum install firewalld -y
systemctl start firewalld
systemctl enable firewalld

firewall-cmd --permanent --add-port=22/tcp
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --reload

yum -y install epel-release
yum -y install nodejs npm vim tmux git
yum -y install golang
mkdir /root/gopath
export GOPATH="/root/gopath/"
go get github.com/ncw/rclone
sleep 5
cp /root/gopath/bin/rclone /usr/bin
npm install fsmonitor
npm install -g fsmonitor
npm install forever
npm install -g forever

cat << RCLONE > /root/.rclone.conf
[remote]
type = swift
user = admin
key = P@ssw0rd!
auth = http://203.154.242.201:5000/v2.0
tenant = admin
region = RegionOne
RCLONE


rclone mkdir remote:uploads
rclone mkdir remote:themes
rclone sync  remote:uploads  /var/www/html/wp-content/uploads
rclone sync  remote:themes  /var/www/html/wp-content/themes

cat << BACKUP > backup.js
var sys = require('sys');
var exec = require('child_process').exec;
function reports(error, stdout, stderr) {sys.puts(stdout)};
fsmonitor = require('fsmonitor');
fsmonitor.watch('/var/www/html/wp-content/uploads', null, function(change) {
console.log("Change detected:\n" + change);

console.log("Added files:    %j", change.addedFiles);
console.log("Modified files: %j", change.modifiedFiles);
console.log("Removed files:  %j", change.removedFiles);

console.log("Added folders:    %j", change.addedFolders);
console.log("Modified folders: %j", change.modifiedFolders);
console.log("Removed folders:  %j", change.removedFolders);
exec('rclone sync /var/www/html/wp-content/uploads  remote:uploads',reports)
});

fsmonitor2 = require('fsmonitor');
fsmonitor2.watch('/var/www/html/wp-content/themes', null, function(change) {
console.log("Change detected:\n" + change);

console.log("Added files:    %j", change.addedFiles);
console.log("Modified files: %j", change.modifiedFiles);
console.log("Removed files:  %j", change.removedFiles);

console.log("Added folders:    %j", change.addedFolders);
console.log("Modified folders: %j", change.modifiedFolders);
console.log("Removed folders:  %j", change.removedFolders);
exec('rclone sync /var/www/html/wp-content/themes  remote:themes', reports)
});
BACKUP
forever start backup.js

systemctl restart httpd.service

params:
 $db_name: {get_param: database_name}
 $db_user: {get_param: database_user}
 $db_password: {get_attr: [database_password, value]}
 $db_host: {get_attr: [db, first_address]}
