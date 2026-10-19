#!/usr/bin/env bash
# Controlled failure: remove / restore ONLY the App-B ICMP echo rule from App-A (10.10.2.10/32).
# Usage: ./04_controlled_failure.sh remove | restore
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
source "$(cd "$(dirname "$0")" && pwd)/ids.env"
case "${1:-}" in
  remove)  aws ec2 revoke-security-group-ingress --group-id "$SG_APP_B" --protocol icmp --port 8-0 --cidr 10.10.2.10/32
           echo "Removed. Now ping 10.20.1.10 from App-A: replies should stop." ;;
  restore) aws ec2 authorize-security-group-ingress --group-id "$SG_APP_B" --protocol icmp --port 8-0 --cidr 10.10.2.10/32
           echo "Restored. Ping again: replies should resume." ;;
  *) echo "Usage: $0 remove|restore"; exit 1 ;;
esac
