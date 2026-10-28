///|
test "interface string formatting retains prefix and scope" {
  let iface = @ipset.ip_interface("192.0.2.7/24")
  assert_eq(iface.format("<16s"), "192.0.2.7/24    ")
  assert_eq(iface.format("*^16s"), "**192.0.2.7/24**")
  assert_eq(iface.format(".9s"), "192.0.2.7")
  assert_eq(
    @ipset.ip_interface("fe80::1%eth0/64").format(">18s"),
    "   fe80::1%eth0/64",
  )
}

///|
test "interface preserves host bits and exposes its associated network" {
  let iface = @ipset.ip_interface("192.0.2.7/24")
  assert_eq(iface.ip().to_string(), "192.0.2.7")
  assert_eq(iface.network().to_string(), "192.0.2.0/24")
  assert_eq(iface.to_string(), "192.0.2.7/24")
  assert_eq(iface.with_netmask(), "192.0.2.7/255.255.255.0")
  assert_eq(iface.with_hostmask(), "192.0.2.7/0.0.0.255")
  assert_eq(iface.to_bytes(), b"\xC0\x00\x02\x07")
  assert_eq(iface.to_bigint(), 3221225991N)
  assert_eq(@ipset.ip_interface("192.0.2.7/255.255.255.0"), iface)
  assert_eq(@ipset.ip_interface("192.0.2.7/0.0.0.255"), iface)
  assert_eq(@ipset.ip_interface("2001:db8::7").prefixlen(), 128)
}

///|
test "interface scope has explicit host and formatted representations" {
  let iface = @ipset.ip_interface("fe80::1%eth0/64")
  assert_eq(iface.to_string(), "fe80::1%eth0/64")
  assert_eq(iface.compressed(), "fe80::1%eth0/64")
  assert_eq(iface.address().to_string(), "fe80::1%eth0")
  assert_eq(iface.ip().to_string(), "fe80::1")
  assert_eq(iface.network().to_string(), "fe80::/64")
  assert_eq(iface.with_prefixlen(), "fe80::1/64")
  assert_eq(iface.with_netmask(), "fe80::1/ffff:ffff:ffff:ffff::")
  assert_eq(iface.exploded(), "fe80:0000:0000:0000:0000:0000:0000:0001/64")
  assert_eq(iface.scope_id(), Some("eth0"))
  assert_true(iface != @ipset.ip_interface("fe80::1%eth1/64"))
}

///|
test "interface properties reflect host except IPv6 loopback and unspecified" {
  assert_true(@ipset.ip_interface("192.168.1.7/24").is_private())
  assert_true(!@ipset.ip_interface("100.64.0.1/10").is_global())
  assert_true(@ipset.ip_interface("8.8.8.8/0").is_global())
  assert_true(@ipset.ip_interface("::1/128").is_loopback())
  assert_true(!@ipset.ip_interface("::1/64").is_loopback())
  assert_true(@ipset.ip_interface("::/128").is_unspecified())
  assert_true(!@ipset.ip_interface("::/64").is_unspecified())
  assert_eq(
    @ipset.ip_interface("::ffff:192.0.2.1/128")
    .ipv4_mapped()
    .unwrap()
    .to_string(),
    "192.0.2.1",
  )
}

///|
test "interfaces compare by network then host and hash consistently" {
  let short = @ipset.ip_interface("192.0.2.1/24")
  let longer = @ipset.ip_interface("192.0.2.1/25")
  assert_true(short < longer)
  assert_true(short != longer)
  assert_eq(short.hash(), @ipset.ip_interface("192.0.2.1/255.255.255.0").hash())
  assert_eq(short.add(1N).to_string(), "192.0.2.2/32")
  assert_eq(short.subtract(1N).to_string(), "192.0.2.0/32")
  assert_eq(short.format("s"), "192.0.2.1/24")
  assert_eq(short.format("#x"), "0xc0000201")
  assert_eq(short.reverse_pointer(), "1.2.0.192.in-addr.arpa")
}

///|
test "dual stack address-plan workflow allocates prefixes and preserves hosts" {
  let pool = @ipset.ip_network("2001:db8::/48")
  let allocations = pool.subnets(new_prefix=64)
  let first = allocations.next().unwrap()
  let second = allocations.next().unwrap()
  assert_eq(second.to_string(), "2001:db8:0:1::/64")
  let gateway = @ipset.IpInterface::from_address(first.nth(1N), 64)
  assert_eq(gateway.to_string(), "2001:db8::1/64")
  assert_eq(gateway.network(), first)
  assert_true(pool.contains(gateway.ip()))
  assert_true(!second.contains(gateway.ip()))
  let available = pool.address_exclude(first).to_array()
  assert_eq(
    available
    .iter()
    .fold(init=0N, fn(total, net) { total + net.num_addresses() }) +
    first.num_addresses(),
    pool.num_addresses(),
  )
}

///|
test "interface mapped masks use hexadecimal hosts and unspecified matches reference" {
  let mapped = @ipset.ip_interface("::ffff:192.0.2.1/120")
  assert_eq(mapped.to_string(), "::ffff:192.0.2.1/120")
  assert_eq(mapped.with_prefixlen(), "::ffff:c000:201/120")
  assert_eq(
    mapped.with_netmask(),
    "::ffff:c000:201/ffff:ffff:ffff:ffff:ffff:ffff:ffff:ff00",
  )
  assert_eq(mapped.with_hostmask(), "::ffff:c000:201/::ff")
  // Unlike Python 3.13.2's mapped-interface formatter, retain the prefix.
  assert_eq(mapped.exploded(), "0000:0000:0000:0000:0000:ffff:192.0.2.1/120")
  for prefix in [0, 16, 32] {
    let iface = @ipset.ip_interface("0.0.0.0/\{prefix}")
    assert_true(!iface.is_unspecified())
    assert_true(iface.ip().is_unspecified())
  }
}

///|
test "interface arithmetic returns full-width interface and clears scope" {
  let iface = @ipset.ip_interface("fe80::1%eth0/64")
  let next = iface.add(1N)
  assert_eq(next.to_string(), "fe80::2/128")
  assert_eq(next.scope_id(), None)
  assert_eq(next.ip(), next.network().network_address())
  assert_eq(iface.subtract(1N).to_string(), "fe80::/128")
  assert_true(
    try {
      ignore(@ipset.ip_interface("::/0").subtract(1N))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@ipset.ip_interface("255.255.255.255/24").add(1N))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "interface values work as Map keys including prefix and scope identity" {
  let values : Map[@ipset.IpInterface, Int32] = Map([])
  let host = @ipset.ip_interface("192.0.2.7/24")
  values[host] = 1
  values[@ipset.ip_interface("192.0.2.7/25")] = 2
  values[@ipset.ip_interface("fe80::1%eth0/64")] = 3
  values[@ipset.ip_interface("fe80::1%eth1/64")] = 4
  assert_eq(values.length(), 4)
  assert_eq(values.get(@ipset.ip_interface("192.0.2.7/255.255.255.0")), Some(1))
  assert_eq(values.get(@ipset.ip_interface("fe80::1%eth0/64")), Some(3))
  assert_eq(values.get(@ipset.ip_interface("fe80::1%eth2/64")), None)
}

///|
test "mapped-zero interface is not the all-zero IPv6 interface" {
  for prefix in [0, 64, 96, 120, 127, 128] {
    let iface = @ipset.ip_interface("::ffff:0.0.0.0/\{prefix}")
    assert_true(!iface.is_unspecified())
    assert_true(iface.ip().is_unspecified())
  }
  assert_true(@ipset.ip_interface("::/128").is_unspecified())
  assert_true(!@ipset.ip_interface("::/127").is_unspecified())
}

///|
test "interface mapped IPv6 uses only the host address" {
  for
    (text, expected) in [
      ("0.0.0.0/0", "::ffff:0.0.0.0"),
      ("192.0.2.7/24", "::ffff:192.0.2.7"),
      ("255.255.255.255/32", "::ffff:255.255.255.255"),
    ] {
    assert_eq(
      @ipset.ip_interface(text).ipv6_mapped().unwrap().to_string(),
      expected,
    )
  }
}
