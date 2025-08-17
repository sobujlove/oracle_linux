#!/bin/bash
# Oracle 19c + APEX + ORDS + Nginx HTTPS Installer for Oracle Linux 9
# Author: Sabuj Khandakar & ChatGPT

set -e

DB_PASS="Oracle123!"
DOMAIN="uparjon.com.bd"
EMAIL="sabuj@uparjon.com.bd"
ORACLE_SID="orcl"
ORACLE_HOME="/opt/oracle/product/19c/dbhome_1"

echo "=== STEP 1: Update OS ==="
sudo dnf update -y
sudo dnf install -y oracle-epel-release-el9 unzip wget tar net-tools dnf-utils zip curl nginx certbot python3-certbot-nginx java-11-openjdk

echo "=== STEP 2: Install Oracle 19c ==="
# Download manually: oracle-database-ee-19c-1.0-1.ol9.x86_64.rpm
if [ ! -f oracle-database-ee-19c-1.0-1.ol9.x86_64.rpm ]; then
  echo "Please download oracle-database-ee-19c-1.0-1.ol9.x86_64.rpm from Oracle and place it here."
  exit 1
fi
sudo dnf localinstall -y oracle-database-ee-19c-1.0-1.ol9.x86_64.rpm

echo "=== STEP 3: Configure Oracle 19c ==="
sudo /etc/init.d/oracledb_ORCLCDB-19c configure || true
sudo systemctl stop oracledb_ORCLCDB-19c || true

echo "=== STEP 4: Create Non-CDB Database ORCL ==="
sudo su - oracle <<EOF
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
dbca -silent -createDatabase \
   -templateName General_Purpose.dbc \
   -gdbname $ORACLE_SID \
   -sid $ORACLE_SID \
   -createAsContainerDatabase false \
   -characterSet AL32UTF8 \
   -memoryPercentage 30 \
   -emConfiguration NONE \
   -datafileDestination '/opt/oracle/oradata' \
   -sysPassword $DB_PASS \
   -systemPassword $DB_PASS \
   -dbsnmpPassword $DB_PASS
EOF

echo "=== STEP 5: Install APEX ==="
cd /opt
wget -q https://download.oracle.com/otn_software/apex/apex-latest.zip
unzip -q apex-latest.zip
cd apex
sudo su - oracle <<EOF
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
sqlplus sys/$DB_PASS@localhost:1521/$ORACLE_SID as sysdba <<SQL
@apexins.sql SYSAUX SYSAUX TEMP /i/
@apxchpwd.sql
$DB_PASS
$DB_PASS
@apex_rest_config.sql
$DB_PASS
$DB_PASS
$DB_PASS
SQL
EOF

echo "=== STEP 6: Install ORDS ==="
cd /opt
wget -q https://download.oracle.com/otn_software/java/ords/ords-latest.zip
unzip -q ords-latest.zip
cd ords
sudo su - oracle <<EOF
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
java -jar ords.war install simple <<ORDS
localhost
1521
$ORACLE_SID
APEX_PUBLIC_USER
$DB_PASS
$DB_PASS
ORDS
EOF

echo "=== STEP 7: Configure Nginx + HTTPS ==="
cat <<NGX | sudo tee /etc/nginx/conf.d/apex.conf
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8080/ords/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
}
NGX

sudo systemctl enable --now nginx
sudo certbot --nginx -d $DOMAIN -m $EMAIL --agree-tos --non-interactive

echo "=== INSTALLATION COMPLETE ==="
echo "Access APEX at: https://$DOMAIN/ords/"
echo "Workspace: INTERNAL | User: ADMIN | Password: $DB_PASS"
