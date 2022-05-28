#!/bin/sh
#Variables
CLUSTER_NAME=$1
MACHINE_TYPE="c2-standard-8"
NUM_NODES=$2
MONITORING_NS="monitoring"
VOLT_NS="voltdb"
KAFKA_NS="kafka"
DOCKER_ID="jadejakajal13"
DOCKER_API="b461d1b4-82c4-499e-afc0-f17943a16411"
DOCKER_EMAIL="jadejakajal13@gmail.com"
MONITORING_VERSION="10.1.0"
VOLT_DEPLPOYMENTNAME="mydb"
PROPERTY_FILE="myproperties.yaml"
LICENSE_FILE="/opt/voltdb/voltdb/license.xml"
COMMANDLOG_ENABLED="false"
SNAPSHOT_ENABLED="false"
ZK_SVC="zookeeper.kafka.svc.cluster.local"

#creating a cluster
#gcloud container clusters create   --machine-type $MACHINE_TYPE  --image-type UBUNTU_CONTAINERD  --num-nodes $NUM_NODES   --cluster-version 1.19.13-gke.1900 $CLUSTER_NAME

gcloud container clusters create  --machine-type $MACHINE_TYPE  --image-type UBUNTU_CONTAINERD  --num-nodes $NUM_NODES --zone us-central1-b  $CLUSTER_NAME


#CPU pinning properties file
#gcloud container clusters create   --system-config-from-file=kubeletConfig.yaml  --machine-type $MACHINE_TYPE  --image-type UBUNTU_CONTAINERD  --num-nodes $NUM_NODES    $CLUSTER_NAME


#creating namespaces
kubectl create namespace $VOLT_NS
kubectl create namespace $MONITORING_NS
kubectl create namespace $KAFKA_NS
#labelling nodes for voltdb
kubectl get nodes | tail -3 | awk -F " " {'print $1'} | xargs -n1 -I {}  kubectl label node {} env=db
#labelling node for test client
kubectl get nodes | head -2| tail -1 | awk -F " " {'print $1'} | xargs -n1 -I {}  kubectl label node {} env=client

#adding helm repos
helm repo add voltdb https://voltdb-kubernetes-charts.storage.googleapis.com
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

#creating docker secret
kubectl create secret docker-registry dockerio-registry --docker-username=$DOCKER_ID \
--docker-password=$DOCKER_API  --docker-email=$DOCKER_EMAIL --namespace $VOLT_NS

kubectl create secret docker-registry dockerio-registry --docker-username=$DOCKER_ID \
--docker-password=$DOCKER_API  --docker-email=$DOCKER_EMAIL 

kubectl get ns 

helm install zookeeper bitnami/zookeeper \
  --set replicaCount=1 \
  --set auth.enabled=false \
  --set allowAnonymousLogin=true --namespace=$KAFKA_NS

#helm install ptest prometheus-community/kube-prometheus-stack --version=$MONITORING_VERSION \
#   --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
#   --set grafana.service.type=LoadBalancer,grafana.adminPassword=admin -n $MONITORING_NS

#helm install ptest voltdb/voltdb-prometheus-dev  \
#   --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
#   --set grafana.service.type=LoadBalancer,grafana.adminPassword=admin -n $MONITORING_NS

helm install monitoring-stack prometheus-community/kube-prometheus-stack --version=30.0.1 -f prom_config.yaml -n monitoring


helm install $VOLT_DEPLPOYMENTNAME voltdb/voltdb --wait --values $PROPERTY_FILE --set metrics.enabled=true \
	--set metrics.delta=true --set cluster.config.deployment.commandlog.enabled=$COMMANDLOG_ENABLED \
	--set cluster.config.deployment.snapshot.enabled=$SNAPSHOT_ENABLED --set-file cluster.config.licenseXMLFile=$LICENSE_FILE -n $VOLT_NS

helm install kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=1 \
  --set externalZookeeper.servers=$ZK_SVC --namespace=$KAFKA_NS

sleep 180

kubectl cp schema/voltdb-chargingdemo.jar  mydb-voltdb-cluster-0:/tmp/ -n $VOLT_NS
#kubectl cp schema/db.sql mydb-voltdb-cluster-0:/tmp/ -n $VOLT_NS

kubectl exec -it mydb-voltdb-cluster-0 -n $VOLT_NS -- sqlcmd < schema/db.sql

#kubectl create -f usersJob.yaml -n $VOLT_NS

echo "IP for UI access"
kubectl get nodes -o wide | tail -1 | awk -F " " {'print $7'}
echo "VolTB Port for UI access"
kubectl get svc -n $VOLT_NS  | grep http |awk -F " " {'print $5'}
echo "grafana Port for UI access"
kubectl get svc -n $MONITORING_NS | grep grafana | awk -F " " {'print $5'}
