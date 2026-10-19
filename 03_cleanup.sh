#!/usr/bin/env bash
# EWB VPC Peering lab - Cleanup. Save your screenshots/output FIRST.
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
source "$(cd "$(dirname "$0")" && pwd)/ids.env"
read -r -p "Delete ALL lab resources in $AWS_DEFAULT_REGION? Type yes: " a; [ "$a" = yes ] || exit 1

echo "Terminating instances..."
aws ec2 terminate-instances --instance-ids "$BASTION" "$APP_A" "$APP_B" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$BASTION" "$APP_A" "$APP_B"

echo "Peering routes and connection..."
if [ -n "${PCX:-}" ]; then
  aws ec2 delete-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16
  aws ec2 delete-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16
  aws ec2 delete-route --route-table-id "$RT_A_PUB"  --destination-cidr-block 10.20.0.0/16
  aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$PCX"
  sleep 5
fi

echo "Security groups..."
for sg in "$SG_BASTION" "$SG_APP_A" "$SG_APP_B"; do aws ec2 delete-security-group --group-id "$sg"; done

echo "Route tables and subnets..."
for a in "$ASSOC_A_PUB" "$ASSOC_A_PRIV" "$ASSOC_B_PRIV"; do aws ec2 disassociate-route-table --association-id "$a"; done
for rt in "$RT_A_PUB" "$RT_A_PRIV" "$RT_B_PRIV"; do aws ec2 delete-route-table --route-table-id "$rt"; done
for s in "$SUB_A_PUB" "$SUB_A_PRIV" "$SUB_B_PRIV"; do aws ec2 delete-subnet --subnet-id "$s"; done

echo "Internet gateway and VPCs..."
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW"
aws ec2 delete-vpc --vpc-id "$VPC_A"
aws ec2 delete-vpc --vpc-id "$VPC_B"

echo "Done. Delete the key pair 'ewb-lab' in EC2 > Key Pairs if you no longer need it, then run the verify commands in the README."
