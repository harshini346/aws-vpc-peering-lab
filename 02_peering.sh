#!/usr/bin/env bash
# EWB VPC Peering lab - Part 2
# Run ONLY AFTER you have captured the baseline failed ping from App-A.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/ids.env"
STUDENT="${STUDENT:-Harshini}"

PCX=$(aws ec2 create-vpc-peering-connection --vpc-id "$VPC_A" --peer-vpc-id "$VPC_B" \
      --query VpcPeeringConnection.VpcPeeringConnectionId --output text)
aws ec2 create-tags --resources "$PCX" --tags Key=Name,Value=ewb-a-b-peer Key=Project,Value=EWB-VPC-Peering Key=Student,Value="$STUDENT"
echo "PCX=$PCX" >> "$DIR/ids.env"

aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-ids "$PCX"
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PCX" >/dev/null

for i in $(seq 1 30); do
  S=$(aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids "$PCX" --query 'VpcPeeringConnections[0].Status.Code' --output text)
  [ "$S" = active ] && break; sleep 4
done
echo "Peering $PCX status: $S"

aws ec2 create-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 create-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 create-route --route-table-id "$RT_A_PUB"  --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null

echo "Peering active and routes added. Run the tests from the README."
for rt in "$RT_A_PRIV" "$RT_B_PRIV" "$RT_A_PUB"; do
  echo "--- $rt"; aws ec2 describe-route-tables --route-table-ids "$rt" \
    --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId,VpcPeeringConnectionId]' --output table
done
