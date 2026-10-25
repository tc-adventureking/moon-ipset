///|
fn main {
  try {
    let allowed = @ipset.IpSet::from_cidrs(["10.0.0.0/24", "2001:db8::/126"])
    let excluded = @ipset.IpSet::from_cidrs(["10.0.0.0/25", "2001:db8::1/128"])
    let remaining = allowed.difference(excluded)
    println("Allowlist minus exclusions:")
    for cidr in remaining.cidrs() {
      println(cidr.to_string())
    }
    println(
      "Contains 10.0.0.200: \{remaining.contains(@ipset.Address::parse("10.0.0.200"))}",
    )
    println(
      "Contains 2001:db8::1: \{remaining.contains(@ipset.Address::parse("2001:db8::1"))}",
    )
  } catch {
    error => println(error.to_string())
  }
}
