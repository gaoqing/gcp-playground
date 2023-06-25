#!/bin/bash

#just use the one set by 'gcloud config set project [your-project-id]'
#PROJECT_ID="arcane-argon-386608"
#gcloud config set project "${PROJECT_ID}"
REGION="asia-east2"
COMPUTE_ZONE="asia-east2-a"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${COMPUTE_ZONE}"

VM_NAME=my-todo-gce-box
NODE_PORT=6006
httpPort6006=6006
httpPort80=80

# toggle of https support, toggle true need more settings, refer to 'doCreate4Https' function at the bottom
IS_HTTPS_TOGGLE_ON=false

staticHtmlFile=sample-todo-website.html
nodeServerFile=sample-node-server.js

######## startup-script for the GCE instance, which provision apps into the VM instance. ########
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
}


function getOrCreateIpAddress(){
  #gcloud compute addresses delete ${THE_IP_ADDRESS_NAME} --global --quiet
  IP_ADDRESSName=$1
  theIp=$(gcloud compute addresses describe ${IP_ADDRESSName} --global --format='get(address)' 2>/dev/null);
  if [ -z "${theIp}" ]; then
     gcloud compute addresses create ${IP_ADDRESSName} --global
     theIp=$(gcloud compute addresses describe ${IP_ADDRESSName} --global --format='get(address)');
  fi
  echo ${theIp};
}


######## Start of GCP infra provisioning ########

##create static ip address
staticIpName=http-todo-app-static-ip
IP_ADDRESS=$(getOrCreateIpAddress ${staticIpName})
echo "For HTTP use IP_ADDRESS: ${IP_ADDRESS}"

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
# https
httpsTargetHttpsProxiesName=https-todo-target-https-proxies
httpsFrontendForwardingRuleName=https-todo-frontend-fwd-rule


# delete relevant things if already exists
gcloud compute forwarding-rules describe ${frontendForwardingRuleName} --global >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute forwarding-rules delete ${frontendForwardingRuleName} --global --quiet;

gcloud compute forwarding-rules describe ${httpsFrontendForwardingRuleName} --global >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute forwarding-rules delete ${httpsFrontendForwardingRuleName} --global --quiet;

gcloud compute target-http-proxies describe ${targetHttpProxiesName} >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute target-http-proxies delete ${targetHttpProxiesName} --quiet

gcloud compute target-https-proxies describe ${httpsTargetHttpsProxiesName} >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute target-https-proxies delete ${httpsTargetHttpsProxiesName} --quiet

gcloud compute url-maps describe ${urlMapsName} >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute url-maps delete ${urlMapsName} --quiet

gcloud compute backend-services describe ${backendServiceName} --global >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute backend-services delete ${backendServiceName} --global --quiet

gcloud compute instance-groups managed describe ${instanceGroupName} --region=${REGION} >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute instance-groups managed delete ${instanceGroupName} --region=${REGION} --quiet

gcloud compute instance-templates describe ${instanceTemplateName} >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute instance-templates delete ${instanceTemplateName} --quiet

gcloud compute health-checks describe ${healthCheckerName} --global >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute health-checks delete ${healthCheckerName} --global --quiet

gcloud compute firewall-rules describe ${firewallAllowX006} >/dev/null 2>&1
[ $? -eq 0 ] && gcloud compute firewall-rules delete ${firewallAllowX006} --quiet


###create instance template
gcloud compute instance-templates create ${instanceTemplateName}  \
  --metadata-from-file startup-script=${startUpScriptName} \
  --machine-type=f1-micro \
  --tags=http-server,https-server,${firewallTagX006} \
  --create-disk=image=projects/ubuntu-os-cloud/global/images/ubuntu-1804-bionic-v20230308,mode=rw,size=10,type=pd-balanced


###create instance group
### add health check for instance group members, use either 1 below
# TCP health check to simply verify that a TCP connection can be established, but not application layer behaviour
gcloud compute health-checks create tcp ${healthCheckerName}  \
  --global \
  --port=${NODE_PORT}  \
  --check-interval=5s \
  --timeout=5s \
  --unhealthy-threshold=2 \
  --healthy-threshold=2

# HTTP health-check, to app health endpoint, test specific to application layer behaviour
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
  --port-name=namedport80
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


echo "(wait for 1 min) Then web server available at: http://${IP_ADDRESS}, or http://${IP_ADDRESS}/index.html. make sure http! "




#######################################################################################################################
#######################################################################################################################

function doCreate4Https(){
  ######### HTTPS support ########

  ### IF want to do https, need a domain before hand, which will be signed by GCP.
  ### Https forwarding rules: https://cloud.google.com/load-balancing/docs/ssl-certificates/google-managed-certs#gcloud
  ### However for newly created GCP managed-cert, need time for GCP signing, my previous test about 1 hour.
  echo "Start to create https relevant resources, it will take a while ......"

  ## use your real domain name below
#  domain='your.real.domain.com'
  domain=$1
  sslCertName=https-todo-app-gcp-cert
  httpsStaticIpName=https-todo-app-static-ip

  HTTPS_IP_ADDRESS=$(getOrCreateIpAddress ${httpsStaticIpName})
  echo "For HTTPS use IP_ADDRESS: ${HTTPS_IP_ADDRESS}"

  gcloud compute ssl-certificates describe ${sslCertName} --global >/dev/null 2>&1
  [ $? -eq 1 ] && gcloud compute ssl-certificates create ${sslCertName} --domains=${domain} --global

  gcloud compute target-https-proxies create ${httpsTargetHttpsProxiesName} \
      --url-map=${urlMapsName} \
      --ssl-certificates=${sslCertName} \
      --global-ssl-certificates \
      --global

  gcloud compute forwarding-rules create ${httpsFrontendForwardingRuleName} \
    --target-https-proxy=${httpsTargetHttpsProxiesName} \
    --load-balancing-scheme=EXTERNAL \
    --ports=443 \
    --address=${HTTPS_IP_ADDRESS} \
    --global

  echo "Need to update your DNS registrar's domain mapping for 'A' record to IP address: ${HTTPS_IP_ADDRESS}"
  echo "Need to wait quite some time(maybe 1 hour) for GCP to provision this cert, in GCP console, go to 'Certificate Manager' page and 'CLASSIC CERTIFICATES' tab to check status"
  echo "After cert status turn into active, can access: https://${domain}/index.html"

}


# enable for HTTPS if toggled on, under the provided domain
YOUR_DOMAIN_NAME='your.real.domain.com'

if [ ${IS_HTTPS_TOGGLE_ON} = true ]; then
  doCreate4Https ${YOUR_DOMAIN_NAME}
fi

