### GCP and App provisions:
<br/>

#### 1. The `start-gce-under-load-balancer.sh` is self-contained provisioning script.
   
It will serve a website automatically, by

- destroy old things firstly if any and then re-create them.
- create instance-template with startup script which will spin up a node server with express to serve todo-app static html.
- relevant firewall-rules(to open ports) created attached to target-tags, which will be used by instance-template. 
- create instance-group backed by that instance-template.
- create http(s) load balancer with backend-services linked to above instance-group.
- with forwarding-rules as front end.
- http requests route -> forwarding-rules -> target-http-proxy -> url-maps -> backend-services -> instance-group -> instance-template -> gce instance -> app

Try steps:
```shell
gcloud auth login
gcloud config set project [your-project-id ]
cd [ dir-of-script]
sh [ start-gce-under-load-balancer.sh | start-gce-instance.sh ]
```
<br/>

#### 2. If want to practise manual steps without using previous self-contained script, can try
- bring up a gce instance manually, to provide startup-script to provision app manually after ssh to the vm box.
- create an image based on the running gce instance, apps/files/libs get baked into the image.
- create instance-template to use the image above, 
  but need to provide startup-script in order to bring up apps(though file are in image), like to navigate to some dir and to start app process, like `node server.js` or `java -jar some.jar` ect
- create instance-group with instance-template as before.
- create load balancer backed by instance-group as before.