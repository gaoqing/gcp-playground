#!/bin/bash

#just use the one set by 'gcloud config set project [your-project-id]'
#PROJECT_ID="splendid-alpha-381707"
#gcloud config set project "${PROJECT_ID}"
REGION="asia-east2"
COMPUTE_ZONE="asia-east2-a"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${COMPUTE_ZONE}"

VM_NAME=gce-test-box
NODE_PORT=6006
proxy80=80
staticHtml=todo-website.html
nodeServerFile=node-server.js

startUpScriptName=gce-test-startup-script.sh

# Startup script for the GCE instance
cat << 'EOF' > ${startUpScriptName}
#!/bin/bash
apt-get update
curl -sL https://deb.nodesource.com/setup_16.x | bash -
apt-get install -y nodejs
apt-get install -y lsof
mkdir /app
cd /app
EOF

# bundle static file to startup script
staticContent=$(cat ./${staticHtml})
cat << EOF >> ${startUpScriptName}
mkdir static
cat << 'EOF2' > static/index.html
${staticContent}
EOF2
EOF

# bundle node server file to startup script
nodeServerJs=$(cat ./${nodeServerFile})
cat << EOF >> ${startUpScriptName}
cat << 'EOF2' > app.js
${nodeServerJs}
EOF2

npm init -y
npm install express
node app.js &
EOF

cat << 'EOF' >> ${startUpScriptName}
# here just only for testing purpose nginx proxy, proxy from 80 to node server ${NODE_PORT}.
# install nginx

apt-get install -y nginx
cat << 'EOF2' > /etc/nginx/sites-available/reverse-proxy.conf
server {
    listen 80;
    server_name my.domain.name.com;

    location / {
        proxy_pass http://localhost:6006;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF2

ln -s /etc/nginx/sites-available/reverse-proxy.conf /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
service nginx restart
EOF

#create static ip address
staticIpName=gce-static-ip-name;
#gcloud compute addresses delete ${staticIpName} --region=${REGION} --quiet 2>/dev/null
ipAddress=$(gcloud compute addresses describe ${staticIpName} --global --format='get(address)' 2>/dev/null);
if [ -z "${ipAddress}" ]; then
   gcloud compute addresses create ${staticIpName} --global
   ipAddress=$(gcloud compute addresses describe ${staticIpName} --global --format='get(address)');
fi
echo "Use IP_ADDRESS: ${ipAddress}";


# delete before using the same instance name
gcloud compute instances delete ${VM_NAME} --zone=${COMPUTE_ZONE} --delete-disks=all --quiet

# create a GCE instance with the startup script and static ip address
gcloud compute instances create ${VM_NAME} \
  --image-family ubuntu-1804-lts \
  --image-project ubuntu-os-cloud \
  --metadata-from-file startup-script=${startUpScriptName} \
  --address=${staticIpName} \
  --tags http-server

FIREWALL_RULE=default-allow-http-${NODE_PORT}-${proxy80};
# delete before create same name;
gcloud compute firewall-rules delete ${FIREWALL_RULE} --quiet

# create a firewall rule to allow incoming traffic on port
gcloud compute firewall-rules create ${FIREWALL_RULE} \
  --allow tcp:${NODE_PORT},tcp:${proxy80} \
  --source-ranges 0.0.0.0/0 \
  --target-tags http-server \
  --description "Allow port ${NODE_PORT}, ${proxy80} access to http-server"

# get the external IP address
EXTERNAL_IP=$(gcloud compute instances describe ${VM_NAME} --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

# print the external IP address
echo "(wait for 30 seconds) Then web server available at: http://${EXTERNAL_IP}:${NODE_PORT}, or by nginx proxy via: http://${EXTERNAL_IP}:${proxy80}/index.html. make sure http!!"
