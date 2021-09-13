# Break down of startCluster.sh

## Set environment variables
Define a set of environment variables that will be used in the rest of the commands.

```sh
iteration=1
region="us-east-2"
cluster_name="eksfg-$iteration"
keyPair="$cluster_name"
awsaccount=$(aws sts get-caller-identity | grep Account | awk -F\" '{print $4}')
```

## Create a key Pair that will be used to access the EKS EC2 Nodes (if required)
```sh
keymaterial=$(aws ec2 create-key-pair --region $region --key-name $keyPair \
      | grep KeyMaterial | awk -F\" '{print $4}')
cat <<EOF > ~/.ssh/$keyPair.pem
$keymaterial
EOF
```

## Set up an EFS file system.
This system uses EFS to pass the raw data files between services. The following command creates and tags the EFS cluster that we will use. For more information about EFS see the [EFS Website](https://aws.amazon.com/efs/)
```sh
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
```

Save the following command in a notepad. If you lose your session you will need to run this command to get your file system id
```sh
file_system_id=$(aws efs describe-file-systems \
        --query FileSystems[?Name==\`EKS-$cluster_name-EFS\`].FileSystemId \
        | grep fs | awk -F\" '{print $2}')
```

## Deploy the EKS infrastructure
In this step the entire EKS infrastructure will deploy. This will take a few minutes. The EKS cluster configuration file states that we want to have managed ec2 nodes and Fargate nodes. EKS will also deploy a managed, resiliant Kubernetes control plane.
```sh
sed -i.orig "s/REGION/$region/g" clusterconfig.yaml
sed -i "s/CLUSTER_NAME/$cluster_name/g" clusterconfig.yaml
cp clusterconfig.yaml clusterconfig.prod.yaml
cp clusterconfig.yaml.orig clusterconfig.yaml
rm clusterconfig.yaml.orig
eksctl create cluster -f clusterconfig.prod.yaml
```

## Configure Kubectl
Now that EKS is deployed we need to configure kubectl to connect to our EKS control plane
```sh
aws eks update-kubeconfig --region $region --name $cluster_name
```

## Cloudwatch Container Insights
[Container Insights from CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
Use CloudWatch Container Insights to collect, aggregate, and summarize metrics and logs from your containerized applications and microservices. Container Insights is available for Amazon Elastic Container Service (Amazon ECS), Amazon Elastic Kubernetes Service (Amazon EKS), and Kubernetes platforms on Amazon EC2. Amazon ECS support includes support for Fargate.

CloudWatch automatically collects metrics for many resources, such as CPU, memory, disk, and network. Container Insights also provides diagnostic information, such as container restart failures, to help you isolate issues and resolve them quickly. You can also set CloudWatch alarms on metrics that Container Insights collects.
```sh
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
[[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
[[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'
sed -i.orig 's/{{cluster_name}}/'${cluster_name}'/;s/{{region_name}}/'${region}'/;s/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/;s/{{http_server_port}}/"'${FluentBitHttpPort}'"/;s/{{read_from_head}}/"'${FluentBitReadFromHead}'"/;s/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' ./cwagent-fluent-bit-quickstart.yaml
cp ./cwagent-fluent-bit-quickstart.yaml ./cwagent-fluent-bit-quickstart.prod.yaml
cp ./cwagent-fluent-bit-quickstart.yaml.orig ./cwagent-fluent-bit-quickstart.yaml
rm ./cwagent-fluent-bit-quickstart.yaml.orig
kubectl apply -f ./cwagent-fluent-bit-quickstart.prod.yaml
```

## IAM node roles for S3 access
Give the EC2 nodes access to S3 for logging and data storage.
```sh
nodeRole=$(aws iam list-roles  | grep eksctl | grep $cluster_name | grep NodeInstanceRole | grep RoleName | awk -F\" '{print $4}')
aws iam attach-role-policy --role-name $nodeRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name $nodeRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy
aws iam attach-role-policy --role-name $nodeRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

## Deploy Kubernetes dashboard
```sh
kubectl apply -f ../metrics/metrics-server.yaml
kubectl apply -f ../metrics/dashboard.yaml
kubectl apply -f ../metrics/eks-admin-service-account.yaml
```

Access to the dashboard will be controlled by a security token. Use the following command to get the token. This token will not change during this session, so you can save it to your notepad.
```sh
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')
```

The endpoint for the dashboard can be found with this command.
```sh
kubectl -n kubernetes-dashboard get service/kubernetes-dashboard | grep dashboard | awk '{print $4}'
```


## Load Balancer controller
The AWS Load Balancer Controller manages AWS Elastic Load Balancers for a Kubernetes cluster. The controller provisions the following resources.

An AWS Application Load Balancer (ALB) when you create a Kubernetes Ingress.

An AWS Network Load Balancer (NLB) when you create a Kubernetes Service of type LoadBalancer. In the past, the Kubernetes in-tree load balancer was used for instance targets, but the AWS Load balancer Controller was used for IP targets. With the AWS Load Balancer Controller version 2.2.0 or later, you can create Network Load Balancers using either target type. For more information about NLB target types, see Target type in the User Guide for Network Load Balancers.
[Load Balancer Controller Documentation](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
```sh
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
```

## EFS CSI
The Amazon EFS Container Storage Interface (CSI) driver provides a CSI interface that allows Kubernetes clusters running on AWS to manage the lifecycle of Amazon EFS file systems.
[EFS CSI Driver Documentation](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)

```sh
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
```

## Create EFS access points for each subnet
```sh
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
```

## Deploy Kafka
This solution uses Kafka for data availability messages that tip services to the availability of new data in EFS
```sh
kubectl apply -f kafka.yaml
```

## Deploy the ETL
With the infrastructure all build and deployed, it is time to deploy our application
```sh
sed -i.orig "s/FILESYSTEM_ID/$file_system_id/g" ../etl-efs/ETL.yaml
cp ../etl-efs/ETL.yaml ../etl-efs/ETL.prod.yaml
cp ../etl-efs/ETL.yaml.orig ../etl-efs/ETL.yaml
kubectl apply -f ../etl-efs/ETL.prod.yaml
```


## Shutdown
### Set environment variables (if required)
Define a set of environment variables that will be used in the rest of the commands.
If you worked through the 'Getting Started' section you should have an EC2 instnace and a command line. Run the following commands in that EC2 instance. Youalso copied the sample code from the git repository.
```sh
iteration=1
region="us-east-2"
cluster_name="eksfg-$iteration"
keyPair="$cluster_name"
awsaccount=$(aws sts get-caller-identity | grep Account | awk -F\" '{print $4}')
file_system_id=$(aws efs describe-file-systems \
        --query FileSystems[?Name==\`EKS-$cluster_name-EFS\`].FileSystemId \
        | grep fs | awk -F\" '{print $2}')
```

## Remove the key pair
```sh
aws ec2 delete-key-pair --key-name $keyPair
```
## Detach IAM roles
```sh
nodeRole=$(aws iam list-roles  | grep eksctl | grep $cluster_name | grep NodeInstanceRole | grep RoleName | awk -F\" '{print $4}')
aws iam detach-role-policy --role-name $nodeRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam detach-role-policy --role-name $nodeRole \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy
aws iam detach-role-policy --role-name $nodeRole \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

## Delete services
```sh
kubectl delete svc --namespace=eksfg-etl etl-ingest
kubectl delete svc dashboard-metrics-scraper
kubectl delete svc kubernetes-dashboard
kubectl delete svc metrics-server
kubectl delete svc --namespace=eksfg-etl kafka-hs
kubectl delete svc --namespace=eksfg-etl zk-cs
kubectl delete svc --namespace=eksfg-etl zk-hs
```

## Remove the security groups
```sh
sg="sg"$(aws ec2 describe-security-groups --output=text |grep eksfg-c-EFS-SG | awk -F'sg' '{print $2}' | awk '{print $1}')
aws ec2 delete-security-group --group-id $sg
```

## Disconnect EFS file system
```sh
# Clean up the EFS
file_system_id=$(aws efs describe-file-systems \
    --query FileSystems[?Name==\`EKS-$cluster_name-EFS\`].FileSystemId \
    | grep fs | awk -F\" '{print $2}')
mounttargets=$(aws efs describe-mount-targets --file-system-id $file_system_id | grep MountTargetId | awk -F\" '{print $4}')

for target in $mounttargets ; do
    aws efs delete-mount-target \
    --mount-target-id  $target
done
```
Wait for the mount targets to delete (approx 30 sec)
```sh
aws efs delete-file-system --file-system-id $file_system_id
```

## Delete the EKS cluster
```sh
eksctl delete cluster -n $cluster_name -r $region
```


## License

Copyright 2021 AWS

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.