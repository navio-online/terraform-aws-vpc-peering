# Providers are required because of cross-region
provider "aws" {
  alias = "requester"
}

provider "aws" {
  alias = "accepter"
}

data "aws_region" "accepter" {
  provider = aws.accepter
}

data "aws_vpc" "requester" {
  provider = aws.requester
  id       = "${var.requester_vpc_id}"
}

data "aws_vpc" "accepter" {
  provider = aws.accepter
  id       = "${var.accepter_vpc_id}"
}

data "aws_caller_identity" "requester" {
  provider = aws.requester
}

data "aws_caller_identity" "accepter" {
  provider = aws.accepter
}

# Create a route
resource "aws_route" "requester_rt" {
  provider                  = aws.requester
  count                     = length(var.accepter_subnet_range)
  route_table_id            = coalesce(var.requester_main_route_table_id, data.aws_vpc.requester.main_route_table_id)
  destination_cidr_block    = element(var.accepter_subnet_range, count.index)
  vpc_peering_connection_id = aws_vpc_peering_connection.requester.id
}

## Create a route
resource "aws_route" "accepter_rt" {
  provider                  = aws.accepter
  count                     = length(var.requester_subnet_range)
  route_table_id            = coalesce(var.accepter_main_route_table_id, data.aws_vpc.accepter.main_route_table_id)
  destination_cidr_block    = element(var.requester_subnet_range, count.index)
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.accepter.vpc_peering_connection_id
}

resource "aws_vpc_peering_connection" "requester" {
  provider    = aws.requester
  vpc_id      = var.requester_vpc_id

  peer_vpc_id   = var.accepter_vpc_id
  peer_region   = data.aws_region.accepter.name
  peer_owner_id = data.aws_caller_identity.accepter.account_id

  tags = merge(
    var.tags,
    map("Name", "To ${var.accepter_name}",
        "requestor_vpc", var.requester_vpc_id,
        "requestor_owner_id", data.aws_caller_identity.requester.account_id,
        "accepter_vpc", var.accepter_vpc_id,
        "accepter_owner_id", data.aws_caller_identity.accepter.account_id,
    )
  )
}

resource "aws_vpc_peering_connection_options" "requester" {
  provider                  = aws.requester

  depends_on                = [aws_vpc_peering_connection_accepter.accepter]

  vpc_peering_connection_id = aws_vpc_peering_connection.requester.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}


# Accepter's side of the connection.
resource "aws_vpc_peering_connection_accepter" "accepter" {
  provider                  = aws.accepter
  vpc_peering_connection_id = aws_vpc_peering_connection.requester.id
  auto_accept               = true

  tags = merge(
    var.tags,
    map("Name", "From ${var.requester_name}",
        "requester_vpc", var.requester_vpc_id,
        "requester_owner_id", data.aws_caller_identity.requester.account_id,
        "accepter_vpc", var.accepter_vpc_id,
        "accepter_owner_id", data.aws_caller_identity.accepter.account_id,
    )
  )
}

resource "aws_vpc_peering_connection_options" "accepter" {
  provider                  = aws.accepter

  depends_on                = [aws_vpc_peering_connection_accepter.accepter]
  
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.accepter.vpc_peering_connection_id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}
