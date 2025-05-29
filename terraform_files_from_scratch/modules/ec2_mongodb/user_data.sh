#!/bin/bash
set -e

apt-get update -y
apt-get upgrade -y
apt-get install -y wget tar unzip awscli cron

wget https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-4.0.28.tgz
tar -xvzf mongodb-linux-x86_64-4.0.28.tgz
sudo mv mongodb-linux-x86_64-4.0.28 /usr/local/mongodb
echo 'export PATH=/usr/local/mongodb/bin:$PATH' >> ~/.bashrc
echo 'export PATH=/usr/local/mongodb/bin:$PATH' >> /home/ubuntu/.bashrc
echo 'export PATH=/usr/local/mongodb/bin:$PATH' >> /root/.bashrc
export PATH=/usr/local/mongodb/bin:$PATH
mkdir -p /data/db
chown -R ubuntu /data/db

cat <<EOF > /etc/systemd/system/mongod.service
[Unit]
Description=MongoDB manual instance
After=network.target

[Service]
ExecStart=/usr/local/mongodb/bin/mongod --auth --dbpath=/data/db
User=ubuntu
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mongod
systemctl start mongod

sleep 10

mongo admin --eval "db.createUser({user:'greg',pwd:'greg123',roles:[{role:'root',db:'admin'}]})"

wget https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu1604-x86_64-100.5.2.tgz
tar -xvzf mongodb-database-tools-*.tgz
mv mongodb-database-tools-*/bin/* /usr/local/bin/

cat <<EOF > /home/ubuntu/backup.sh
#!/bin/bash
TIMESTAMP="\$(date +'%Y-%m-%d')"
BACKUP_DIR="/tmp/mongo-backup-\$TIMESTAMP"
MONGODUMP="/usr/local/bin/mongodump"
AWS="/usr/bin/aws"
mkdir -p \$BACKUP_DIR >> /tmp/backup-debug.log 2>&1
\$MONGODUMP -u greg -p greg123 --authenticationDatabase admin --out \$BACKUP_DIR >> /tmp/backup-debug.log 2>&1
\$AWS s3 cp \$BACKUP_DIR s3://${s3_bucket_name}/\$TIMESTAMP --recursive >> /tmp/backup-debug.log 2>&1
rm -rf \$BACKUP_DIR >> /tmp/backup-debug.log 2>&1
EOF

chmod +x /home/ubuntu/backup.sh
chown ubuntu:ubuntu /home/ubuntu/backup.sh

if [ -f /home/ubuntu/backup.sh ]; then
  set +e
  CRON_LINE="* 19 * * * /home/ubuntu/backup.sh >> /home/ubuntu/backup.log 2>&1"
  sudo -u ubuntu crontab -l 2>/dev/null | grep -v backup.sh > /tmp/current_cron || true
  grep -F "\$CRON_LINE" /tmp/current_cron || echo "\$CRON_LINE" >> /tmp/current_cron
  sudo -u ubuntu crontab /tmp/current_cron
  rm /tmp/current_cron
  set -e
fi