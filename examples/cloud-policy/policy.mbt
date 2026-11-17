///|
fn lines(text : String) -> Array[String] {
  text.split("\n").map(line => line.to_owned()).to_array()
}

///|
fn cidr_json(set : @net.IpSet) -> Json {
  Json::array(set.cidrs().map(cidr => Json::string(cidr.to_string())))
}

///|
/// Parse a fixed, real dual-stack inventory and subtract one region's coverage.
/// Returns complete canonical results, counts and membership answers.
pub fn run() -> Json raise {
  let source = lines(source_prefixes)
  let exclusions = lines(exception_prefixes)
  let all = @net.IpSet::from_cidrs(source)
  let exceptions = @net.IpSet::from_cidrs(exclusions)
  let allowed = all.difference(exceptions)
  let mut v4 = 0N
  let mut v6 = 0N
  for cidr in allowed.cidrs() {
    let network = @net.IpNetwork::from_cidr(cidr)
    if network.version() == 4 {
      v4 += network.num_addresses()
    } else {
      v6 += network.num_addresses()
    }
  }
  Json::object({
    "source_prefixes": Json::number(source.length().to_double()),
    "exception_prefixes": Json::number(exclusions.length().to_double()),
    "normalized": cidr_json(all),
    "exceptions": cidr_json(exceptions),
    "allowed": cidr_json(allowed),
    "members": Json::array(
      lines(query_addresses).map(address => {
        Json::boolean(allowed.contains(@net.Address::parse(address)))
      }),
    ),
    "ipv4_addresses": Json::string(v4.to_string()),
    "ipv6_addresses": Json::string(v6.to_string()),
  })
}

///|
pub fn summary(result : Json) -> Json {
  let fields = match result {
    Object(fields) => fields
    _ => abort("invalid report")
  }
  fn array_size(value : Json) -> Json {
    match value {
      Array(items) => Json::number(items.length().to_double())
      _ => abort("invalid report array")
    }
  }
  let members = match fields["members"] {
    Array(items) => items
    _ => abort("invalid members")
  }
  Json::object({
    "source_prefixes": fields["source_prefixes"],
    "exception_prefixes": fields["exception_prefixes"],
    "normalized_cidrs": array_size(fields["normalized"]),
    "allowed_cidrs": array_size(fields["allowed"]),
    "ipv4_addresses": fields["ipv4_addresses"],
    "ipv6_addresses": fields["ipv6_addresses"],
    "queries": array_size(fields["members"]),
    "matched_queries": Json::number(
      members.filter(x => x == Json::boolean(true)).length().to_double(),
    ),
  })
}
