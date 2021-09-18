#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
iteration=1
region="us-east-2"
while getopts i:r:fe flag
do
    case "${flag}" in
        i) iteration=${OPTARG};;
        r) region=${OPTARG};;
    esac
done
cluster_name="eksfg-$iteration"
keyPair="$cluster_name"
awsaccount=$(aws sts get-caller-identity | grep Account | awk -F\" '{print $4}')

echo "iteration:$iteration cluster:$cluster_name region:$region keyPair:$keyPair account=$awsaccount"

# Create a KeyPair
keymaterial=$(aws ec2 create-key-pair --region $region --key-name $keyPair \
      | grep KeyMaterial | awk -F\" '{print $4}')
cat <<EOF > ~/.ssh/$keyPair.pem
$keymaterial
EOF
 
# Create the EFS

file_system_id=$(aws efs create-file-system \
    --region $region \
    --performance-mode generalPurpose \
    --query 'FileSystemId' \
    --tags "Key=EKSCluster,Value=$cluster_name" \
    --encrypted \
    --output text)
 sleep 5
 aws efs tag-resource \
    --resource-id $file_system_id \
    --tags Key="Name",Value="EKS-$cluster_name-EFS" \
    --region $region 

echo "Deploying EKS with Node groups and Fargate"
sed -i.orig "s/REGION/$region/g" clusterconfig.yaml
sed -i "s/CLUSTER_NAME/$cluster_name/g" clusterconfig.yaml
cp clusterconfig.yaml clusterconfig.prod.yaml
cp clusterconfig.yaml.orig clusterconfig.yaml
rm clusterconfig.yaml.orig
eksctl create cluster -f clusterconfig.prod.yaml

echo "Configuing K8S" 
#callerId=$(aws sts get-caller-identity | grep Arn | awk -F\" '{print $4}')
aws eks update-kubeconfig --region $region --name $cluster_name # --role-arn $callerId

echo "Deploying Cloud Watch Container Insights"
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
[[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
[[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'
sed -i.orig 's/{{cluster_name}}/'${cluster_name}'/;s/{{region_name}}/'${region}'/;s/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/;s/{{http_server_port}}/"'${FluentBitHttpPort}'"/;s/{{read_from_head}}/"'${FluentBitReadFromHead}'"/;s/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' ./cwagent-fluent-bit-quickstart.yaml 
cp ./cwagent-fluent-bit-quickstart.yaml ./cwagent-fluent-bit-quickstart.prod.yaml 
cp ./cwagent-fluent-bit-quickstart.yaml.orig ./cwagent-fluent-bit-quickstart.yaml 
rm ./cwagent-fluent-bit-quickstart.yaml.orig
kubectl apply -f ./cwagent-fluent-bit-quickstart.prod.yaml 


#update node role to include s3 access
echo "Allow access to S3"
nodeRole=$(aws iam list-roles  | grep eksctl | grep $cluster_name | grep NodeInstanceRole | grep RoleName | awk -F\" '{print $4}')
aws iam attach-role-policy --role-name $nodeRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name $nodeRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy
aws iam attach-role-policy --role-name $nodeRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

#deploy metrics server
echo "Deploy K8S dashboard"
kubectl apply -f ../metrics/metrics-server.yaml
kubectl apply -f ../metrics/dashboard.yaml
kubectl apply -f ../metrics/eks-admin-service-account.yaml #TODO: reduce privledges

sleep 10 

# Get the dashboard eks-admin auth token
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')

# Get the dashboard endpoint
dashboardEndpoint=$(kubectl -n kubernetes-dashboard get service/kubernetes-dashboard | grep dashboard | awk '{print $4}')
echo "******************************************************"
echo "Dashboard endpoint:  https://$dashboardEndpoint"
echo "******************************************************"

sleep 10

####Deploy the ETL stack


echo "configure EFS and K8S"

#efs csi  
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/ecr/?ref=release-1.3.4"
aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy_$cluster_name \
    --policy-document file://efs-iam-policy.json
eksctl create iamserviceaccount \
    --name efs-csi-controller-sa \
    --namespace kube-system \
    --cluster $cluster_name \
    --attach-policy-arn arn:aws:iam::$awsaccount:policy/AmazonEKS_EFS_CSI_Driver_Policy_$cluster_name \
    --approve \
    --override-existing-serviceaccounts \
    --region $region 
    
vpc_id=$(aws ec2 describe-vpcs \
    --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name" | \
    grep VpcId | awk -F\" '{print $4}')
cidr_range=$(aws ec2 describe-vpcs \
    --vpc-ids $vpc_id \
    --query "Vpcs[].CidrBlock" \
    --output text)
security_group_id=$(aws ec2 create-security-group \
    --group-name "$cluster_name-EFS-SG" \
    --description "EFS Security Group for EKS Cluster $cluster_name" \
    --vpc-id $vpc_id \
    --output text)
aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --protocol tcp \
    --port 2049 \
    --cidr $cidr_range
subnets=$(aws ec2 describe-subnets     --filters "Name=vpc-id,Values=$vpc_id"\
    --query 'Subnets[*].{SubnetId: SubnetId,AvailabilityZone: AvailabilityZone,CidrBlock: CidrBlock}'  \
    --output table | grep subnet- | awk '{print $6}')
for subnet in $subnets ; do
    # Mount EFS targets to each subnet
    aws efs create-mount-target \
    --file-system-id $file_system_id \
    --subnet-id $subnet \
    --security-groups $security_group_id
done
sed -i.orig "s/FILESYSTEM_ID/$file_system_id/g" ../etl-efs/EFSPV.yaml
cp ../etl-efs/EFSPV.yaml ../etl-efs/EFSPV.prod.yaml
mv ../etl-efs/EFSPV.yaml.orig ../etl-efs/EFSPV.yaml
kubectl apply -f ../etl-efs/EFSPV.prod.yaml

#load balancer controller
curl -o elb_iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy$cluster_name \
    --policy-document file://elb_iam_policy.json
eksctl create iamserviceaccount \
  --cluster=$cluster_name \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$awsaccount:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve
kubectl apply \
    --validate=false \
    -f https://github.com/jetstack/cert-manager/releases/download/v1.1.1/cert-manager.yaml
curl -o v2_2_0_full.yaml https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/v2_2_0_full.yaml
sleep 10
kubectl apply -f v2_2_0_full.yaml

sleep 60

### Deploy kafka
## K8S based Kafka
kubectl apply -f kafka.yaml
## Managed Kafka Service - todo
# aws cloudformation create-stack  --stack-name eksfg-3-mks-2 --parameters ParameterKey=SubnetIds,ParameterValue=subnet-0fe8a544788f3c068\\,subnet-0e0a159a6f135cc4d\\,subnet-08e87d921bb94d431 --template-body file://mks-cf.yaml

# Deploy the ETL pipeline to EKS
kubectl apply -f ../etl-efs/ETL.yaml

## Deploy the test harness
sleep 120
kubectl apply -f ../testharness/testharness.yaml




