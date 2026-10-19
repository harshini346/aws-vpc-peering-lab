# AWS VPC Peering Lab (EWB Courses, Project 01)

Two VPCs (10.10.0.0/16 and 10.20.0.0/16) connected by VPC peering. Private EC2 instances talk over private IPs; a public bastion in VPC A is the only SSH entry point (ProxyJump).

| Resource | Name | Address |
|---|---|---|
| VPC A | ewb-vpc-a | 10.10.0.0/16 |
| Public subnet A | ewb-a-public | 10.10.1.0/24 (bastion 10.10.1.10) |
| Private subnet A | ewb-a-private | 10.10.2.0/24 (App-A 10.10.2.10) |
| VPC B | ewb-vpc-b | 10.20.0.0/16 |
| Private subnet B | ewb-b-private | 10.20.1.0/24 (App-B 10.20.1.10) |
| Peering | ewb-a-b-peer | requester A, accepter B |

## Repo contents
- `01_build_base.sh` builds VPCs, subnets, IGW, route tables, security groups, instances
- `02_peering.sh` creates and accepts peering, adds the three peering routes
- `04_controlled_failure.sh` removes/restores the App-B ICMP rule
- `03_cleanup.sh` deletes everything
- `ssh_config.example` SSH ProxyJump config

## Order of work
1. EC2 > Key Pairs: create RSA key `ewb-lab` (.pem) in the same Region; keep it on your laptop only.
2. CloudShell: `chmod +x *.sh && ./01_build_base.sh <your-public-IP>`
3. Laptop: edit `~/.ssh/config` from `ssh_config.example`; `ssh ewb-bastion`, then `ssh ewb-app-a`.
4. **Baseline** (in App-A): `hostname; hostname -I; ping -c 4 10.20.1.10` -> no replies. Screenshot.
5. CloudShell: `./02_peering.sh`
6. Tests: App-A `ping -c 4 10.20.1.10`; laptop `ssh ewb-app-b`, then in App-B `ping -c 4 10.10.2.10`. Screenshot each.
7. Isolation: EC2 console, App-A and App-B have no public IPv4.
8. Controlled failure: `./04_controlled_failure.sh remove`, ping from App-A (fails), `./04_controlled_failure.sh restore`, ping again (works).
9. Capture screenshots of routes, SGs, peering (Active) and instances, then `./03_cleanup.sh`.

## Why it works
- Peering is only the link; each side needs a route to the other VPC's CIDR (forward and return).
- The bastion's subnet needs the 10.20.0.0/16 peering route because ProxyJump makes the bastion open the connection to App-B, so App-B sees the bastion's private IP as source.
- Peering is non-transitive and gives VPC B no internet access through VPC A's IGW.

Never commit your `.pem` key or `ids.env`.
