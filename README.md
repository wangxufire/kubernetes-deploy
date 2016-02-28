Docker集群管理工具 Google Kubernetes 部署文档
------------------------------------

### 组件信息

 组件 	   |版本      
:----------|:---------
Kubernetes | v1.1.7    
docker 	   | 1.8.2    
etcd 	   | 2.1.1    
flannel    | 0.5.3    

### 本文Kubernetes版本为 v1.0.3，v1.1.7也已验证

　v1.0版本后安装部署差异应该不大，主要差别应该在应用集群的yaml配置文件

　<font color="red">由于GFW的原因，所有gcr.io/google_containers/的镜像都需翻墙下载。</font>

### Deployment on CentOS 7
以三台主机示例，一台master，两台minion。

* 在所有主机执行
<pre>
systemctl stop firewalld && systemctl disable firewalld
</pre>

#### 配置Kubernetes主节点(master:172.17.13.26)

* 通过yum(或dnf)安装Kubernetes及etcd
<pre>
yum install -y etcd kubernetes
</pre>
* 修改etcd配置(/etc/etcd/etcd.conf)监听所有ip
<pre>
ETCD_NAME=kubernetes
ETCD_DATA_DIR="/var/lib/etcd/kubernetes.etcd"
<font color="red">ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"</font>
ETCD_ADVERTISE_CLIENT_URLS="http://localhost:2379"
</pre>

 > Tip 此处为单节点简单配置，etcd也可集群配置

* 修改Kubernetes API Server配置文件(/etc/kubernetes/apiserver)
<pre>
KUBE_API_ADDRESS="--address=0.0.0.0"
KUBE_API_PORT="--port=8080"
KUBELET_PORT="--kubelet_port=10250"
KUBE_ETCD_SERVERS="--etcd_servers=http://127.0.0.1:2379"
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"
KUBE_ADMISSION_CONTROL="--admission_control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ResourceQuota"
KUBE_API_ARGS="--service-node-port-range=30000-40000 --service_account_key_file=/opt/kubernetes/key/serviceaccount.key"
</pre>
* 修改Kubernetes Controller Manager配置文件(/etc/kubernetes/controller-manager)
<pre>
KUBE_CONTROLLER_MANAGER_ARGS="--service_account_private_key_file=/opt/kubernetes/key/serviceaccount.key"
</pre>
* 生成账户密钥
<pre>
mkdir -p /opt/kubernetes/key
openssl genrsa -out /opt/kubernetes/key/serviceaccount.key 2048
</pre>
* 启动etcd、kube-apiserver、kube-controller-manager、kube-scheduler服务
<pre>
for SERVICES in etcd kube-apiserver kube-controller-manager kube-scheduler;
do
　systemctl restart $SERVICES
　systemctl enable $SERVICES
　systemctl status $SERVICES 
done
</pre>
* 在etcd中定义flannel网络配置
<pre>
etcdctl mk /atomic.io/network/config '{"Network":"172.17.0.0/16"}'
</pre>
* 查询节点信息(此时没有节点)
<pre>
kubectl get nodes
</pre>

#### 配置Kubernetes Minions(nodes:{172.17.13.128,172.17.13.129})

* 通过yum(或dnf)安装Kubernetes、docker、flannel及cadvisor
<pre>
yum install -y docker cadvisor flannel kubernetes
</pre>
* 修改flannel配置(/etc/sysconfig/flanneld)
<pre>
FLANNEL_ETCD="http://172.17.13.26:2379"
</pre>
* 修改Kubernetes默认配置(/etc/kubernetes/config)连接到master
<pre>
KUBE_MASTER="--master=http://172.17.13.26:8080"
</pre>
* 修改kubelet配置(/etc/kubernetes/kubelet)
<pre>
KUBELET_ADDRESS="--address=0.0.0.0"
KUBELET_PORT="--port=10250"
<font># change the hostname to this host’s IP address</font>
<font color="red">KUBELET_HOSTNAME="--hostname_override=172.17.13.128"</font>
KUBELET_API_SERVER="--api_servers=http://172.17.13.26:8080"
KUBELET_ARGS=""
</pre>
* 启动kube-proxy、kubelet、docker、flanneld服务
<pre>
for SERVICES in kube-proxy kubelet docker flanneld; 
do
　systemctl restart $SERVICES
　systemctl enable $SERVICES
　systemctl status $SERVICES 
done
</pre>
其他节点配置类似

* 返回mater节点查询节点信息(此时可以看到配置的两个节点信息)
<pre>
kubectl get --all-namespaces nodes
</pre>
<pre>
NAME            LABELS                                 STATUS    AGE
172.17.13.128   kubernetes.io/hostname=172.17.13.128   Ready     2h
172.17.13.129   kubernetes.io/hostname=172.17.13.129   Ready     2h
</pre>

#### 创建应用集群服务

* 在master节点配置集群方案
如果需要namespace，需先创建namespace
<pre>
mkdir -p /opt/kubernetes/namespace
cd /opt/kubernetes/namespace
vi na.yaml
</pre>
配置见master/opt/kubernetes/namespace/na.yaml </br>
创建集群文件
<pre>
mkdir -p /opt/kubernetes/cluster
cd /opt/kubernetes/cluster
</pre>
以redis集群示例
<pre>
vi redis-cluster.yaml
</pre>
配置见master/opt/kubernetes/cluster/redis-cluster.yaml

* 在各个minion节点执行
<pre>
docker pull docker.io/kubernetes/pause
docker tag docker.io/kubernetes/pause gcr.io/google_containers/pause:0.8.0
docker tag gcr.io/google_containers/pause:0.8.0 gcr.io/google_containers/pause
</pre>

 > 因为GFW的原因无法在gcr.io下载镜像

　　pause为kubernetes所必须的镜像，用于管理各个Pods之间的网络

* 在master节点启动集群服务
<pre>
kubectl create -f /opt/kubernetes/cluster/redis-cluster.yaml 
</pre>
输出:
<pre>
services/redis-master
replicationcontrollers/redis-master
</pre>
查看Controller Manager
<pre>
kubectl get --all-namespaces rc
</pre>
输出:
<pre>
CONTROLLER     CONTAINER(S)   IMAGE(S)          SELECTOR                             REPLICAS
redis-master   master         docker.io/redis   app=redis,role=master,tier=backend   3
</pre>
查看服务
<pre>
kubectl get --all-namespaces svc
</pre>
输出:
<pre>
NAME           LABELS                                    SELECTOR                             IP(S)            PORT(S)
kubernetes     component=apiserver,provider=kubernetes   <font><</font>none<font>></font>                               10.254.0.1       443/TCP
redis-master   app=redis,role=master,tier=backend        app=redis,role=master,tier=backend   10.254.160.170   6379/TCP
</pre>
查看Pods
<pre>
kubectl get --all-namespaces pods
</pre>
输出:
<pre>
NAME                 READY     STATUS    RESTARTS   AGE
redis-master-80mnc   1/1       Running   0          1h
redis-master-fnkxg   1/1       Running   0          1h
redis-master-ig7i0   1/1       Running   0          1h
</pre>

#### 节点负载

可在master通过nginx(可用镜像)分发流量到各个节点，对外输出统一服务地址。
由于集群本身有负载均衡所以即使nginx将请求转发到节点1最终被调用的服务也可能是节点2提供的。

常用命令(待完善)
--------------

kubectl cluster-info
kubectl get nodes

kubectl get namespaces

kubectl get svc
kubectl get rc
kubectl get pods
kubectl logs <pod_name>

kubectl describe pods/redis-master-dz33o

kubectl create -f redis-cluster.yaml 
kubectl delete -f redis-cluster.yaml

kubectl exec -ti <podid> -c <containername> --namespace="kube-system" -- env

kubectl get pods --sort-by=.status.containerStatuses[0].restartCount

异常终止信息
kubectl get pods/pod-w-message -o go-template="{{range .status.containerStatuses}}{{.lastState.terminated.message}}{{end}}"
$ kubectl get pods/pod-w-message -o go-template="{{range .status.containerStatuses}}{{.lastState.terminated.exitCode}}{{end}}"
