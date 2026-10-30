///|
fn summarize_policy() -> Array[String] raise {
  let assigned = @net.IpSet::from_cidrs(["192.0.2.0/24", "2001:db8::/126"])
  let reserved = @net.IpSet::from_cidrs(["192.0.2.64/26", "2001:db8::2/127"])
  assigned.difference(reserved).cidrs().map(cidr => cidr.to_string())
}

///|
fn main {
  try {
    println("Address inventory:")
    for line in address_inventory() {
      println(line)
    }
    println("Subnet allocation:")
    for line in subnet_plan() {
      println(line)
    }
    println("Dual-stack interface configuration:")
    for line in interface_config() {
      println(line)
    }
    println("Policy after exclusions:")
    for network in summarize_policy() {
      println(network)
    }
  } catch {
    error => println(error.to_string())
  }
}

///|
// Scenario 1: validate inventory values and produce normalized host metadata.
fn address_inventory() -> Array[String] raise {
  ["192.168.1.7", "100.64.0.1", "2001:0DB8::1"].map(text => {
    let address = @net.ip_address(text)
    "\{address}: private=\{address.is_private()}, global=\{address.is_global()}"
  })
}

///|
// Scenario 2: split a site allocation into four VLANs and choose first hosts.
fn subnet_plan() -> Array[String] raise {
  @net.ip_network("192.168.10.0/24")
  .subnets(new_prefix=26)
  .map(fn(network) {
    let gateway = network.hosts().next().unwrap()
    "\{network}: gateway=\{gateway}, mask=\{network.netmask()}"
  })
  .to_array()
}

///|
// Scenario 3: retain configured hosts, validate membership and inspect IPv6 lazily.
fn interface_config() -> Array[String] raise {
  let v4 = @net.IpInterface::from_address_mask(
    @net.ip_address("192.168.10.7"),
    "255.255.255.192",
  )
  let v6 = @net.ip_interface("2001:db8:10::7/64")
  assert_true(v4.network().contains(v4.ip()))
  assert_true(v6.network().contains(v6.ip()))
  [
    "host=\{v4.ip()}, network=\{v4.network()}",
    "host=\{v6.ip()}, network=\{v6.network()}",
    "IPv6 count=\{v6.network().num_addresses()}",
  ] +
  v6.network().hosts().take(3).map(a => a.to_string()).to_array()
}

///|
test "inventory distinguishes private global and shared space" {
  assert_eq(address_inventory(), [
    "192.168.1.7: private=true, global=false", "100.64.0.1: private=false, global=false",
    "2001:db8::1: private=true, global=false",
  ])
}

///|
test "site subnet plan produces four nonoverlapping VLANs" {
  assert_eq(subnet_plan(), [
    "192.168.10.0/26: gateway=192.168.10.1, mask=255.255.255.192", "192.168.10.64/26: gateway=192.168.10.65, mask=255.255.255.192",
    "192.168.10.128/26: gateway=192.168.10.129, mask=255.255.255.192", "192.168.10.192/26: gateway=192.168.10.193, mask=255.255.255.192",
  ])
}

///|
test "dual stack configuration preserves hosts and uses bounded IPv6 iteration" {
  assert_eq(interface_config(), [
    "host=192.168.10.7, network=192.168.10.0/26", "host=2001:db8:10::7, network=2001:db8:10::/64",
    "IPv6 count=18446744073709551616", "2001:db8:10::1", "2001:db8:10::2", "2001:db8:10::3",
  ])
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
