#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
iteration=1
region="us-east-2"
while getopts i:r:e flag
do
    case "${flag}" in
        i) iteration=${OPTARG};;
        r) region=${OPTARG};;
        e) efs='true';;
    esac
done
cluster_name="eksfg-$iteration"
keyPair="$cluster_name"
echo "$iteration $cluster_name $region $keyPair"

#delete the keys
aws ec2 delete-key-pair --key-name $keyPair

nodeRole=$(aws iam list-roles  | grep eksctl | grep $cluster_name | grep NodeInstanceRole | grep RoleName | awk -F\" '{print $4}')
aws iam detach-role-policy --role-name $nodeRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam detach-role-policy --role-name $nodeRole \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy
aws iam detach-role-policy --role-name $nodeRole \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy    

# Clean up the services
kubectl delete svc --namespace=eksfg-etl etl-ingest
kubectl delete svc --namespace=eksfg-etl-bus kafka-hs
kubectl delete svc --namespace=eksfg-etl-bus zk-cs
kubectl delete svc --namespace=eksfg-etl-bus zk-hs
kubectl delete svc --namespace=kubernetes-dashboard dashboard-metrics-scraper
kubectl delete svc --namespace=kube-system metrics-server
kubectl delete svc --namespace=kubernetes-dashboard kubernetes-dashboard
kubectl delete svc --namespace=eksfg-etl etl-testharness

# Clean up the EFS
file_system_id=$(aws efs describe-file-systems \
    --query FileSystems[?Name==\`EKS-$cluster_name-EFS\`].FileSystemId \
    | grep fs | awk -F\" '{print $2}')
mounttargets=$(aws efs describe-mount-targets --file-system-id $file_system_id | grep MountTargetId | awk -F\" '{print $4}')

for target in $mounttargets ; do
    aws efs delete-mount-target \
    --mount-target-id  $target
done  
sleep 30
aws efs delete-file-system --file-system-id $file_system_id
sleep 10
sg="sg"$(aws ec2 describe-security-groups --output=text |grep EFS | grep $cluster_name | awk -F'sg' '{print $2}' | awk '{print $1}')
aws ec2 delete-security-group --group-id $sg

eksctl delete cluster -n $cluster_name -r $region



