#!/usr/bin/env bash
# EWB VPC Peering lab - Part 1
# Builds VPC A, VPC B, subnets, IGW, route tables, security groups and 3 EC2 instances.
# Run in AWS CloudShell:  ./01_build_base.sh <your-laptop-public-IPv4>
set -euo pipefail

MY_IP="${1:?Usage: ./01_build_base.sh <your-laptop-public-IPv4>}"
[[ "$MY_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "That is not an IPv4 address"; exit 1; }

STUDENT="${STUDENT:-Harshini}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
AZ="${AWS_DEFAULT_REGION}a"
KEY_NAME="ewb-lab"
OUT="$(cd "$(dirname "$0")" && pwd)/ids.env"
: > "$OUT"

echo "Region: $AWS_DEFAULT_REGION  AZ: $AZ  Type: $INSTANCE_TYPE"

aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1 || {
  echo "Key pair '$KEY_NAME' not found. Create it in EC2 > Key Pairs (RSA, .pem) in this Region first."; exit 1; }

tag() { # resource-id name
  aws ec2 create-tags --resources "$1" --tags Key=Name,Value="$2" Key=Project,Value=EWB-VPC-Peering Key=Student,Value="$STUDENT"
}
save() { echo "$1=$2" >> "$OUT"; }

echo "== VPC A =="
VPC_A=$(aws ec2 create-vpc --cidr-block 10.10.0.0/16 --query Vpc.VpcId --output text); tag "$VPC_A" ewb-vpc-a; save VPC_A "$VPC_A"
SUB_A_PUB=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.1.0/24 --availability-zone "$AZ" --query Subnet.SubnetId --output text); tag "$SUB_A_PUB" ewb-a-public; save SUB_A_PUB "$SUB_A_PUB"
SUB_A_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.2.0/24 --availability-zone "$AZ" --query Subnet.SubnetId --output text); tag "$SUB_A_PRIV" ewb-a-private; save SUB_A_PRIV "$SUB_A_PRIV"

IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text); tag "$IGW" ewb-igw-a; save IGW "$IGW"
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"

RT_A_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_A" --query RouteTable.RouteTableId --output text); tag "$RT_A_PUB" ewb-rt-a-public; save RT_A_PUB "$RT_A_PUB"
ASSOC_A_PUB=$(aws ec2 associate-route-table --route-table-id "$RT_A_PUB" --subnet-id "$SUB_A_PUB" --query AssociationId --output text); save ASSOC_A_PUB "$ASSOC_A_PUB"
aws ec2 create-route --route-table-id "$RT_A_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null

RT_A_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_A" --query RouteTable.RouteTableId --output text); tag "$RT_A_PRIV" ewb-rt-a-private; save RT_A_PRIV "$RT_A_PRIV"
ASSOC_A_PRIV=$(aws ec2 associate-route-table --route-table-id "$RT_A_PRIV" --subnet-id "$SUB_A_PRIV" --query AssociationId --output text); save ASSOC_A_PRIV "$ASSOC_A_PRIV"

echo "== VPC B =="
VPC_B=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 --query Vpc.VpcId --output text); tag "$VPC_B" ewb-vpc-b; save VPC_B "$VPC_B"
SUB_B_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_B" --cidr-block 10.20.1.0/24 --availability-zone "$AZ" --query Subnet.SubnetId --output text); tag "$SUB_B_PRIV" ewb-b-private; save SUB_B_PRIV "$SUB_B_PRIV"
RT_B_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_B" --query RouteTable.RouteTableId --output text); tag "$RT_B_PRIV" ewb-rt-b-private; save RT_B_PRIV "$RT_B_PRIV"
ASSOC_B_PRIV=$(aws ec2 associate-route-table --route-table-id "$RT_B_PRIV" --subnet-id "$SUB_B_PRIV" --query AssociationId --output text); save ASSOC_B_PRIV "$ASSOC_B_PRIV"

echo "== Security groups =="
sg() { # name vpc
  local id; id=$(aws ec2 create-security-group --group-name "$1" --description "$1 EWB VPC peering lab" --vpc-id "$2" --query GroupId --output text)
  tag "$id" "$1"; echo "$id"
}
SG_BASTION=$(sg ewb-sg-bastion "$VPC_A"); save SG_BASTION "$SG_BASTION"
SG_APP_A=$(sg ewb-sg-app-a "$VPC_A");     save SG_APP_A "$SG_APP_A"
SG_APP_B=$(sg ewb-sg-app-b "$VPC_B");     save SG_APP_B "$SG_APP_B"

ing() { aws ec2 authorize-security-group-ingress --group-id "$1" --protocol "$2" --port "$3" --cidr "$4" >/dev/null; }
ing "$SG_BASTION" tcp 22   "$MY_IP/32"
ing "$SG_APP_A"   tcp 22   10.10.1.10/32
ing "$SG_APP_A"   icmp 8-0 10.20.1.10/32   # echo request from App-B
ing "$SG_APP_B"   tcp 22   10.10.1.10/32
ing "$SG_APP_B"   icmp 8-0 10.10.2.10/32   # echo request from App-A

echo "== Instances =="
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
launch() { # name subnet ip sg public(yes|no)
  local pub="--no-associate-public-ip-address"; [ "$5" = yes ] && pub="--associate-public-ip-address"
  local t="{Key=Name,Value=$1},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT}"
  aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
    --subnet-id "$2" --private-ip-address "$3" --security-group-ids "$4" $pub \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,DeleteOnTermination=true}' \
    --tag-specifications "ResourceType=instance,Tags=[$t]" "ResourceType=volume,Tags=[$t]" \
    --query 'Instances[0].InstanceId' --output text
}
BASTION=$(launch ewb-bastion "$SUB_A_PUB"  10.10.1.10 "$SG_BASTION" yes); save BASTION "$BASTION"
APP_A=$(launch ewb-app-a    "$SUB_A_PRIV" 10.10.2.10 "$SG_APP_A"   no);  save APP_A "$APP_A"
APP_B=$(launch ewb-app-b    "$SUB_B_PRIV" 10.20.1.10 "$SG_APP_B"   no);  save APP_B "$APP_B"

echo "Waiting for instances to pass status checks (a few minutes)..."
aws ec2 wait instance-status-ok --instance-ids "$BASTION" "$APP_A" "$APP_B"

BASTION_IP=$(aws ec2 describe-instances --instance-ids "$BASTION" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
save BASTION_PUBLIC_IP "$BASTION_IP"

echo
echo "DONE. Put this in ~/.ssh/config as BASTION_PUBLIC_IP: $BASTION_IP"
echo "IDs saved in $OUT  (copy them into your report: Checkpoints 01 and 02)"
cat "$OUT"
