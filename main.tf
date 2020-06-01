# Providers are required because of cross-region
provider "aws" {
  alias = "requester"
}

provider "aws" {
  alias = "accepter"
}

data "aws_region" "accepter" {
  count    = local.is_one_way_only ? 0 : 1
  provider = aws.accepter
}

data "aws_vpc" "requester" {
  provider = aws.requester
  id       = "${var.requester_vpc_id}"
}

data "aws_vpc" "accepter" {
  count    = local.is_one_way_only ? 0 : 1
  provider = aws.accepter
  id       = "${var.accepter_vpc_id}"
}

data "aws_caller_identity" "requester" {
  provider = aws.requester
}

data "aws_caller_identity" "accepter" {
  count    = local.is_one_way_only ? 0 : 1
  provider = aws.accepter
}

locals {
  is_one_way_only = (var.requester_only == "true")
  accepter_account_id = local.is_one_way_only ? var.accepter_id : data.aws_caller_identity.accepter[0].account_id

  is_local = (!local.is_one_way_only && (data.aws_caller_identity.requester.account_id == local.accepter_account_id))

  requester_subnet_ranges = length(var.requester_subnet_ranges) > 0 ? var.requester_subnet_ranges : [data.aws_vpc.requester.cidr_block]
  accepter_subnet_ranges  = length(var.accepter_subnet_ranges)  > 0 ? var.accepter_subnet_ranges  : [data.aws_vpc.accepter[0].cidr_block]

  requester_route_table_ids = length(var.requester_route_table_ids) > 0 ? var.requester_route_table_ids : [data.aws_vpc.requester.main_route_table_id]
  accepter_route_table_ids  = length(var.accepter_route_table_ids)  > 0 ? var.accepter_route_table_ids  : [data.aws_vpc.accepter[0].main_route_table_id]

  requester_routes = [
    for pair in setproduct(local.accepter_subnet_ranges, local.requester_route_table_ids) : {
      cidr_block     = pair[0]
      route_table_id = pair[1]
    }
  ]

  accepter_routes = local.is_one_way_only ? [] : [
    for pair in setproduct(local.requester_subnet_ranges, local.accepter_route_table_ids) : {
      cidr_block     = pair[0]
      route_table_id = pair[1]
    }
  ]
}

# Create a route
resource "aws_route" "requester" {
  provider = aws.requester

  for_each = {
    for route in local.requester_routes : "${route.cidr_block}.${route.route_table_id}" => route
  }
  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.requester.id
}

## Create a route
resource "aws_route" "accepter" {
  provider = aws.accepter

  for_each = {
    for route in local.accepter_routes : "${route.cidr_block}.${route.route_table_id}" => route
  }
  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr_block
  vpc_peering_connection_id = local.is_local ? aws_vpc_peering_connection.requester.id : aws_vpc_peering_connection_accepter.accepter[0].vpc_peering_connection_id
}

resource "aws_vpc_peering_connection" "requester" {
  provider    = aws.requester

  vpc_id        = var.requester_vpc_id
  peer_vpc_id   = var.accepter_vpc_id
  peer_region   = local.is_local ? null : (local.is_one_way_only ? var.accepter_region : data.aws_region.accepter[0].name)
  peer_owner_id = local.accepter_account_id
  auto_accept   = local.is_local

  dynamic requester {
    for_each = local.is_local ? ["do-it"] : []
    content {
      allow_remote_vpc_dns_resolution = true
    }
  }

  dynamic accepter {
    for_each = local.is_local ? ["do-it"] : []
    content {
      allow_remote_vpc_dns_resolution = true
    }
  }

  tags = merge(
    var.tags,
    map("Name", local.is_local ?  "Local ${var.requester_name} to ${var.accepter_name}" : "Requester: from ${var.requester_name} to ${var.accepter_name}",
        "requester_vpc", var.requester_vpc_id,
        "requester_owner_id", data.aws_caller_identity.requester.account_id,
        "accepter_vpc", var.accepter_vpc_id,
        "accepter_owner_id", local.accepter_account_id,
    )
  )
}

resource "aws_vpc_peering_connection_options" "requester" {
  count      = (local.is_local || local.is_one_way_only) ? 0 : 1
  provider   = aws.requester
  depends_on = [aws_vpc_peering_connection_accepter.accepter]

  vpc_peering_connection_id = aws_vpc_peering_connection.requester.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}


# Accepter's side of the connection.
resource "aws_vpc_peering_connection_accepter" "accepter" {
  count       = (local.is_local || local.is_one_way_only) ? 0 : 1
  provider    = aws.accepter
  auto_accept = true

  vpc_peering_connection_id = aws_vpc_peering_connection.requester.id

  tags = merge(
    var.tags,
    map("Name", "Accepter: from ${var.requester_name} to ${var.accepter_name}",
        "requester_vpc", var.requester_vpc_id,
        "requester_owner_id", data.aws_caller_identity.requester.account_id,
        "accepter_vpc", var.accepter_vpc_id,
        "accepter_owner_id", local.accepter_account_id,
    )
  )
}

resource "aws_vpc_peering_connection_options" "accepter" {
  count      = (local.is_local || local.is_one_way_only) ? 0 : 1
  provider   = aws.accepter
  depends_on = [ aws_vpc_peering_connection_accepter.accepter ]
  
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.accepter[0].vpc_peering_connection_id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}
