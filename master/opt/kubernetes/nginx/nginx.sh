#########################################################################
# File Name: rabbitmq.sh
# Author: liyue
# mail: liyue@hd123.com
# Created Time: Sat Nov 28 17:10:20 2015
#########################################################################
#!/bin/bash

docker rm -f ng
docker run --name ng --net=host -v /opt/kubernetes/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -d docker.io/nginx
docker ps -a
