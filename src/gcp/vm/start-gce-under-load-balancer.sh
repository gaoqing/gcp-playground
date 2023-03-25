#!/bin/bash

#just use the one set by 'gcloud config set project [your-project-id]'
#PROJECT_ID="splendid-alpha-381707"
#gcloud config set project "${PROJECT_ID}"
REGION="asia-east2"
COMPUTE_ZONE="asia-east2-a"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${COMPUTE_ZONE}"

VM_NAME=my-todo-gce-box
NODE_PORT=6006
httpPort6006=6006
httpPort80=80

staticHtmlFile=todo-website.html
nodeServerFile=node-server.js

## Startup script for the GCE instance, which will be run to provision apps inside the VM.
startUpScriptName=gce-todo-startup-script.sh
echo "" > ${startUpScriptName}

cat << 'EOF' >> ${startUpScriptName}
#!/bin/bash
apt-get update
curl -sL https://deb.nodesource.com/setup_16.x | bash -
apt-get install -y nodejs
apt-get install -y lsof
mkdir /app && cd /app
EOF

## bundle static file to startup script
staticContent=$(cat ./${staticHtmlFile})
cat << EOF >> ${startUpScriptName}
mkdir static
cat << 'EOF2' > static/index.html
${staticContent}
EOF2
EOF

## bundle node server file to startup script
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
# here just for testing purpose nginx proxy only, proxy from 80 to node server ${NODE_PORT}.
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
## End of startup-script.sh


staticIpName=todo-app-static-ip;
##create static ip address
#gcloud compute addresses delete ${staticIpName} --global --quiet
ipAddress=$(gcloud compute addresses describe ${staticIpName} --global --format='get(address)' 2>/dev/null);
if [ -z "${ipAddress}" ]; then
   gcloud compute addresses create ${staticIpName} --global
   ipAddress=$(gcloud compute addresses describe ${staticIpName} --global --format='get(address)');
fi
echo "Use IP_ADDRESS: ${ipAddress}";


### names variable
instanceTemplateName=my-todo-app-template
instanceGroupName=my-todo-instance-group
healthCheckerName=my-todo-app-health-check
backendServiceName=my-todo-backend-service
urlMapsName=my-todo-url-maps
targetHttpProxiesName=my-todo-target-http-proxies
frontendForwardingRuleName=my-todo-frontend-fwd-rule
firewallAllowX006=firewall-allow-x006
firewallTagX006=firewall-allowx006-ports


# delete relevant things before re-create
# append 2>/dev/null if want to ignore remove error, like not found error
gcloud compute forwarding-rules delete ${frontendForwardingRuleName} --global --quiet
gcloud compute target-http-proxies delete ${targetHttpProxiesName} --quiet
gcloud compute url-maps delete ${urlMapsName} --quiet
gcloud compute backend-services remove-backend ${backendServiceName} --instance-group=${instanceGroupName} --instance-group-region=${REGION} --global --quiet
gcloud compute backend-services delete ${backendServiceName}  --global --quiet
gcloud compute instance-groups managed delete ${instanceGroupName} --region=${REGION} --quiet
gcloud compute instance-templates delete ${instanceTemplateName} --quiet
gcloud compute health-checks delete ${healthCheckerName}  --global --quiet
gcloud compute firewall-rules delete ${firewallAllowX006} --quiet


###create instance template
gcloud compute instance-templates create ${instanceTemplateName}  \
  --metadata-from-file startup-script=${startUpScriptName} \
  --machine-type=f1-micro \
  --tags=http-server,https-server,${firewallTagX006} \
  --create-disk=image=projects/ubuntu-os-cloud/global/images/ubuntu-1804-bionic-v20230308,mode=rw,size=10,type=pd-balanced


###create instance group
###add health check for instance group members
gcloud compute health-checks create tcp ${healthCheckerName}  \
  --global \
  --port=${NODE_PORT}  \
  --check-interval=5s \
  --timeout=5s \
  --unhealthy-threshold=2 \
  --healthy-threshold=2

#gcloud compute health-checks create http ${healthCheckerName}  \
#  --request-path=/ \
#  --port=${NODE_PORT}  \
#  --check-interval=5s \
#  --timeout=5s \
#  --unhealthy-threshold=2 \
#  --healthy-threshold=2 \
#  --global


gcloud compute instance-groups managed create ${instanceGroupName} \
  --region=${REGION} \
  --template=${instanceTemplateName} \
  --size=1

gcloud compute instance-groups managed set-named-ports ${instanceGroupName}  \
  --region=${REGION} \
  --named-ports=namedport6006:${httpPort6006},namedport80:${httpPort80}

## create load balancer related
gcloud compute backend-services create ${backendServiceName} \
  --global \
  --protocol=HTTP \
  --load-balancing-scheme=EXTERNAL \
  --health-checks=${healthCheckerName} \
  --port-name=namedport80 \
#  --port-name=namedport6006

gcloud compute backend-services add-backend ${backendServiceName} \
  --instance-group=${instanceGroupName} \
  --instance-group-region=${REGION} \
  --global

gcloud compute url-maps create ${urlMapsName} --default-service=${backendServiceName}

gcloud compute target-http-proxies create ${targetHttpProxiesName} --url-map=${urlMapsName}

gcloud compute forwarding-rules create ${frontendForwardingRuleName} \
  --target-http-proxy=${targetHttpProxiesName} \
  --load-balancing-scheme=EXTERNAL \
  --ports=80 \
  --address=${staticIpName} \
  --global

# create firewall to allow ingress traffic
gcloud compute firewall-rules create ${firewallAllowX006} \
  --direction=INGRESS \
  --priority=5000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:6006,tcp:80,tcp:8006,tcp:9006 \
  --target-tags=${firewallTagX006}


echo "(wait for 30 seconds) Then web server available at: http://${ipAddress}, or http://${ipAddress}/index.html. make sure http! "
