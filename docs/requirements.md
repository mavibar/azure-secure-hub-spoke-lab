# Secure Azure Application Lab Requirements

## Business Requirement

Deploy a three-tier application environment in Azure using an enterprise-style hub-and-spoke network architecture.

## Network Requirements

Hub VNet:
10.10.0.0/16

Management subnet:
10.10.1.0/24

Reserved Azure Firewall subnet:
10.10.2.0/26

Reserved Gateway subnet:
10.10.3.0/27

Application Spoke:
10.20.0.0/16

Web subnet:
10.20.1.0/24

Application subnet:
10.20.2.0/24

Database subnet:
10.20.3.0/24

## Security Requirements

1. Application and database servers must not have public IP addresses.
2. Internet traffic must never directly access the application or database tiers.
3. Web tier may communicate with application tier only on required application ports.
4. Application tier may communicate with database tier only on the database port.
5. Database tier must not initiate connections to web tier.
6. Administrative traffic must eventually originate from the management network.
7. Hub and workload spoke must use VNet peering.
8. Infrastructure must ultimately be reproducible through Terraform.
9. Secrets must not be stored in Git.
10. All resources must be tagged with environment, project, owner and managedBy.