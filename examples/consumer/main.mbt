///|
fn summarize_policy() -> Array[String] raise {
  let assigned = @net.IpSet::from_cidrs(["192.0.2.0/24", "2001:db8::/126"])
  let reserved = @net.IpSet::from_cidrs(["192.0.2.64/26", "2001:db8::2/127"])
  assigned.difference(reserved).cidrs().map(cidr => cidr.to_string())
}

///|
fn main {
  try {
    for network in summarize_policy() {
      println(network)
    }
  } catch {
    error => println(error.to_string())
  }
}

///|
test "separate module consumes public API" {
  assert_eq(summarize_policy(), [
    "192.0.2.0/26", "192.0.2.128/25", "2001:db8::/127",
  ])
  let address = @net.Address::parse("2001:db8::ffff:ffff")
  let next = address.next().unwrap()
  assert_eq(next.to_string(), "2001:db8::1:0:0")
  let interval = @net.Interval::new(address, next)
  let set = @net.IpSet::from_ranges([interval])
  assert_true(set.contains(address))
  assert_eq(set.intervals().length(), 1)
}
