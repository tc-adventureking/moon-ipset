///|
fn network_parse_rejected(text : String, strict~ : Bool = true) -> Bool {
  try {
    ignore(@ipset.IpNetwork::parse(text, strict~))
    false
  } catch {
    _ => true
  }
}

///|
test "network accepts host-width defaults and contiguous netmask or hostmask" {
  let samples = [
    ("192.0.2.7", "192.0.2.7/32"),
    ("2001:db8::1", "2001:db8::1/128"),
    ("192.0.2.0/255.255.255.0", "192.0.2.0/24"),
    ("192.0.2.0/0.0.0.255", "192.0.2.0/24"),
    ("0.0.0.0/0.0.0.0", "0.0.0.0/0"),
    ("192.0.2.7/255.255.255.255", "192.0.2.7/32"),
    ("192.0.2.0/024", "192.0.2.0/24"),
    ("::/000", "::/0"),
  ]
  for (input, expected) in samples {
    assert_eq(@ipset.ip_network(input).to_string(), expected)
  }
  assert_true(network_parse_rejected("192.0.2.7/24"))
  assert_eq(
    @ipset.ip_network("192.0.2.7/24", strict=false).to_string(),
    "192.0.2.0/24",
  )
  for
    invalid in [
      "192.0.2.0/255.0.255.0", "192.0.2.0/0.255.0.255", "::/ffff::", "::/129", "192.0.2.0/33",
      "::/-1", "::/+64", "::/", "::/64/64", "::/999999999999999999999999",
    ] {
    assert_true(network_parse_rejected(invalid, strict=false), msg=invalid)
  }
  // The legacy convenience API retains its non-strict default.
  assert_eq(@ipset.Cidr::parse("192.0.2.7/24").to_string(), "192.0.2.0/24")
}

///|
test "network exact masks and 129-bit IPv6 cardinality" {
  let v4 = @ipset.ip_network("192.0.2.0/27")
  assert_eq(v4.num_addresses(), 32N)
  assert_eq(v4.netmask().to_string(), "255.255.255.224")
  assert_eq(v4.hostmask().to_string(), "0.0.0.31")
  assert_eq(v4.broadcast_address().to_string(), "192.0.2.31")
  assert_eq(v4.with_hostmask(), "192.0.2.0/0.0.0.31")
  let v6 = @ipset.ip_network("::/0")
  assert_eq(
    v6.num_addresses().to_string(),
    "340282366920938463463374607431768211456",
  )
  assert_eq(v6.netmask().to_string(), "::")
  assert_eq(
    v6.hostmask().to_string(),
    "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
  )
  assert_eq(
    @ipset.ip_network("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128").num_addresses(),
    1N,
  )
}

///|
test "host iteration handles IPv4 and IPv6 endpoint semantics" {
  let samples = [
    ("192.0.2.0/30", ["192.0.2.1", "192.0.2.2"]),
    ("192.0.2.0/31", ["192.0.2.0", "192.0.2.1"]),
    ("192.0.2.1/32", ["192.0.2.1"]),
    ("2001:db8::/126", ["2001:db8::1", "2001:db8::2", "2001:db8::3"]),
    ("2001:db8::/127", ["2001:db8::", "2001:db8::1"]),
    ("2001:db8::1/128", ["2001:db8::1"]),
  ]
  for (text, expected) in samples {
    assert_eq(
      @ipset.ip_network(text).hosts().map(a => a.to_string()).to_array(),
      expected,
    )
  }
  assert_eq(@ipset.ip_network("192.0.2.0/30").iter().count(), 4)
  let all_v6 = @ipset.ip_network("::/0").iter()
  assert_eq(all_v6.next().unwrap().to_string(), "::")
  assert_eq(all_v6.next().unwrap().to_string(), "::1")
  let host_v6 = @ipset.ip_network("::/0").hosts()
  assert_eq(host_v6.next().unwrap().to_string(), "::1")
}

///|
test "network indexing is exact at negative and 128-bit limits" {
  let n = @ipset.ip_network("2001:db8::/64")
  assert_eq(n.nth(0N).to_string(), "2001:db8::")
  assert_eq(n.nth(-1N).to_string(), "2001:db8::ffff:ffff:ffff:ffff")
  assert_eq(n.nth(-(1N << 64)).to_string(), "2001:db8::")
  for index in [1N << 64, -(1N << 64) - 1N] {
    assert_true(
      try {
        ignore(n.nth(index))
        false
      } catch {
        _ => true
      },
    )
  }
  let all = @ipset.ip_network("::/0")
  assert_eq(
    all.nth((1N << 128) - 1N).to_string(),
    "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
  )
}

///|
test "subnet allocation and supernet preserve coverage without enumeration" {
  let n = @ipset.ip_network("192.0.2.0/24")
  let children = n.subnets(new_prefix=26).to_array()
  assert_eq(children.map(c => c.to_string()), [
    "192.0.2.0/26", "192.0.2.64/26", "192.0.2.128/26", "192.0.2.192/26",
  ])
  for child in children {
    assert_true(child.subnet_of(n))
    assert_eq(child.supernet(new_prefix=24), n)
  }
  assert_eq(n.subnets(prefixlen_diff=0).next().unwrap(), n)
  assert_eq(n.supernet(prefixlen_diff=0), n)
  assert_true(
    try {
      ignore(n.subnets(new_prefix=23))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(n.subnets(new_prefix=26, prefixlen_diff=2))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(n.supernet(new_prefix=25))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(n.supernet(prefixlen_diff=-1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(n.subnets(prefixlen_diff=2147483647))
      false
    } catch {
      _ => true
    },
  )
  let huge = @ipset.ip_network("::/0").subnets(new_prefix=128)
  assert_eq(huge.next().unwrap().to_string(), "::/128")
  assert_eq(huge.next().unwrap().to_string(), "::1/128")
  assert_eq(@ipset.ip_network("0.0.0.0/0").supernet().to_string(), "0.0.0.0/0")
}

///|
test "network relations reject mixed families and support equal blocks" {
  let n = @ipset.ip_network("192.0.2.0/24")
  let small = @ipset.ip_network("192.0.2.128/25")
  assert_true(n.contains(@ipset.ip_address("192.0.2.255")))
  assert_true(!n.contains(@ipset.ip_address("192.0.3.0")))
  assert_true(!n.contains(@ipset.ip_address("::ffff:192.0.2.1")))
  assert_true(n.overlaps(small))
  assert_true(n.supernet_of(small))
  assert_true(n.subnet_of(n))
  assert_true(!n.overlaps(@ipset.ip_network("::/0")))
  assert_true(
    try {
      ignore(n.subnet_of(@ipset.ip_network("::/0")))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "network exclusion emits sibling-first exact complement" {
  let n = @ipset.ip_network("192.0.2.0/28")
  let hole = @ipset.ip_network("192.0.2.1/32")
  let remainder = n.address_exclude(hole).to_array()
  assert_eq(remainder.map(c => c.to_string()), [
    "192.0.2.8/29", "192.0.2.4/30", "192.0.2.2/31", "192.0.2.0/32",
  ])
  assert_eq(
    remainder
    .iter()
    .fold(init=0N, fn(total, item) { total + item.num_addresses() }),
    15N,
  )
  assert_eq(n.address_exclude(n).count(), 0)
  assert_true(
    try {
      ignore(n.address_exclude(@ipset.ip_network("192.0.3.0/24")))
      false
    } catch {
      _ => true
    },
  )
  let full = @ipset.ip_network("::/0")
  let removed = @ipset.ip_network("::1/128")
  let parts = full.address_exclude(removed).to_array()
  assert_eq(parts.length(), 128)
  assert_eq(
    parts.iter().fold(init=0N, fn(total, item) { total + item.num_addresses() }) +
    1N,
    full.num_addresses(),
  )
}

///|
test "summarize and collapse reuse exact set kernel" {
  let range = @ipset.summarize_address_range(
    @ipset.ip_address("192.0.2.1"),
    @ipset.ip_address("192.0.2.6"),
  )
  assert_eq(range.map(n => n.to_string()), [
    "192.0.2.1/32", "192.0.2.2/31", "192.0.2.4/31", "192.0.2.6/32",
  ])
  let joined = @ipset.collapse_addresses([
    @ipset.ip_network("192.0.2.128/25"),
    @ipset.ip_network("192.0.2.0/25"),
    @ipset.ip_network("192.0.2.1/32"),
  ])
  assert_eq(joined.map(n => n.to_string()), ["192.0.2.0/24"])
  assert_true(
    try {
      ignore(
        @ipset.collapse_addresses([
          @ipset.ip_network("0.0.0.0/0"),
          @ipset.ip_network("::/0"),
        ]),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @ipset.summarize_address_range(
          @ipset.ip_address("::2"),
          @ipset.ip_address("::1"),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "network classifiers have network-wide Python semantics" {
  for all in ["0.0.0.0/0", "::/0"] {
    let n = @ipset.ip_network(all)
    assert_true(n.is_global())
    assert_true(!n.is_private())
  }
  let shared = @ipset.ip_network("100.64.0.0/10")
  assert_true(!shared.is_private() && !shared.is_global())
  assert_true(@ipset.ip_network("192.0.0.0/24").is_private())
  assert_true(!@ipset.ip_network("192.0.0.9/32").is_private())
  // Network private tables intentionally differ from mapped-address properties.
  assert_true(@ipset.ip_network("::ffff:8.8.8.8/128").is_private())
  assert_true(@ipset.ip_network("127.0.0.0/8").is_loopback())
  assert_true(@ipset.ip_network("fe80::/10").is_link_local())
  assert_true(@ipset.ip_network("fec0::/10").is_site_local())
  assert_true(@ipset.ip_network("ff00::/8").is_multicast())
}

///|
test "network and interface binary and integer constructors preserve family" {
  assert_eq(@ipset.IpNetwork::from_bigint(0N).to_string(), "0.0.0.0/32")
  assert_eq(
    @ipset.IpNetwork::from_bigint(0N, family=@ipset.V6, prefix=0).to_string(),
    "::/0",
  )
  assert_eq(
    @ipset.IpNetwork::from_bytes(b"\xC0\x00\x02\x00", prefix=24).to_string(),
    "192.0.2.0/24",
  )
  assert_true(
    try {
      ignore(@ipset.IpNetwork::from_bigint(-1N))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@ipset.IpNetwork::from_bytes(b"\x01\x02\x03"))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    @ipset.IpInterface::from_bytes(b"\xC0\x00\x02\x07", prefix=24).to_string(),
    "192.0.2.7/24",
  )
  assert_eq(
    @ipset.IpInterface::from_bigint(1N, family=@ipset.V6, prefix=64).to_string(),
    "::1/64",
  )
}

///|
test "scoped networks preserve scope only for unchanged base addresses" {
  let n = @ipset.ip_network("fe80::%eth0/64")
  assert_eq(n.network_address().to_string(), "fe80::%eth0")
  assert_eq(n.broadcast_address().scope_id(), None)
  assert_eq(n.nth(0N).to_string(), "fe80::")
  assert_eq(n.subnets().next().unwrap().to_string(), "fe80::/65")
  assert_eq(n.supernet().to_string(), "fe80::/63")
  assert_eq(
    @ipset.ip_network("fe80::1%eth0/64", strict=false).to_string(),
    "fe80::/64",
  )
  assert_true(n != @ipset.ip_network("fe80::%eth1/64"))
  assert_eq(
    @ipset.ip_network("fe80::1%eth0/128").hosts().next().unwrap().to_string(),
    "fe80::1%eth0",
  )
}

///|
test "mapped network expansion is hexadecimal rather than mapped address format" {
  assert_eq(
    @ipset.ip_network("::ffff:192.0.2.0/120").exploded(),
    "0000:0000:0000:0000:0000:ffff:c000:0200/120",
  )
  assert_eq(
    @ipset.ip_network("fe80::%eth0/64").exploded(),
    "fe80:0000:0000:0000:0000:0000:0000:0000%eth0/64",
  )
}

///|
test "networks work as Map keys including prefix and scoped base identity" {
  let values : Map[@ipset.IpNetwork, Int32] = Map([])
  values[@ipset.ip_network("192.0.2.0/24")] = 1
  values[@ipset.ip_network("192.0.2.0/25")] = 2
  values[@ipset.ip_network("fe80::%eth0/64")] = 3
  values[@ipset.ip_network("fe80::%eth1/64")] = 4
  assert_eq(values.length(), 4)
  assert_eq(values.get(@ipset.ip_network("192.0.2.0/255.255.255.0")), Some(1))
  assert_eq(values.get(@ipset.ip_network("fe80::%eth0/64")), Some(3))
  assert_eq(values.get(@ipset.ip_network("fe80::%eth2/64")), None)
}

///|
test "version specific network and interface factories enforce address family" {
  assert_eq(@ipset.ipv4_network("192.0.2.0/24").version(), 4)
  assert_eq(@ipset.ipv6_network("2001:db8::/32").version(), 6)
  assert_eq(@ipset.ipv4_interface("192.0.2.1/24").version(), 4)
  assert_eq(@ipset.ipv6_interface("2001:db8::1/32").version(), 6)
  assert_true(
    try {
      ignore(@ipset.ipv4_network("::/0"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@ipset.ipv6_network("0.0.0.0/0"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@ipset.ipv4_interface("::1/128"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@ipset.ipv6_interface("192.0.2.1/24"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "invalid dotted masks report prefix errors instead of address errors" {
  for
    mask in [
      "255.255.255.999", "255.255.255", "255.255.01.0", "0.0.0.-1", "255.0.255.0",
    ] {
    assert_true(
      try {
        ignore(@ipset.ip_network("192.0.2.0/\{mask}"))
        false
      } catch {
        @ipset.InvalidPrefix(actual) => actual == mask
        _ => false
      },
    )
    assert_true(
      try {
        ignore(@ipset.ip_interface("192.0.2.7/\{mask}"))
        false
      } catch {
        @ipset.InvalidPrefix(actual) => actual == mask
        _ => false
      },
    )
  }
  // A malformed host address still reports the address-specific variant.
  assert_true(
    try {
      ignore(@ipset.ip_network("192.0.2.999/24"))
      false
    } catch {
      @ipset.InvalidAddress(actual) => actual == "192.0.2.999"
      _ => false
    },
  )
}

///|
test "typed network mask construction accepts prefixes netmasks and hostmasks" {
  let address = @ipset.ip_address("192.0.2.0")
  for mask in ["24", "024", "255.255.255.0", "0.0.0.255"] {
    assert_eq(
      @ipset.IpNetwork::from_address_mask(address, mask).to_string(),
      "192.0.2.0/24",
    )
  }
  assert_eq(
    @ipset.IpNetwork::from_address_mask(@ipset.ip_address("0.0.0.0"), "0.0.0.0").to_string(),
    "0.0.0.0/0",
  )
  let host = @ipset.ip_address("192.0.2.7")
  for mask in ["255.255.255.255", "0032"] {
    assert_eq(
      @ipset.IpNetwork::from_address_mask(host, mask).to_string(),
      "192.0.2.7/32",
    )
  }
  assert_eq(
    @ipset.IpNetwork::from_address_mask(host, "0.0.0.255", strict=false).to_string(),
    "192.0.2.0/24",
  )
  assert_true(
    try {
      ignore(@ipset.IpNetwork::from_address_mask(host, "255.255.255.0"))
      false
    } catch {
      @ipset.HostBitsSet(_) => true
      _ => false
    },
  )
  let scoped = @ipset.ip_address("fe80::%eth0")
  assert_eq(
    @ipset.IpNetwork::from_address_mask(scoped, "064").to_string(),
    "fe80::%eth0/64",
  )
  for mask in ["", "033", "255.0.255.0", "255.255.255.999", "0.255.0.255"] {
    assert_true(
      try {
        ignore(@ipset.IpNetwork::from_address_mask(address, mask))
        false
      } catch {
        @ipset.InvalidPrefix(actual) => actual == mask
        _ => false
      },
    )
  }
  for mask in ["129", "ffff:ffff:ffff:ffff::", "255.255.255.0"] {
    assert_true(
      try {
        ignore(@ipset.IpNetwork::from_address_mask(scoped, mask))
        false
      } catch {
        @ipset.InvalidPrefix(actual) => actual == mask
        _ => false
      },
    )
  }
}

///|
test "scoped network relations and range covers use numeric address semantics" {
  let plain = @ipset.ip_network("fe80::/64")
  let a = @ipset.ip_network("fe80::%a/64")
  let b = @ipset.ip_network("fe80::%b/64")
  assert_true(a != b && a != plain)
  for left in [plain, a, b] {
    for right in [plain, a, b] {
      // Python rejects containment when scope differs at equal base values.
      assert_true(left.subnet_of(right))
      assert_true(left.supernet_of(right))
      assert_eq(left.address_exclude(right).count(), 0)
      assert_eq(
        left
        .address_exclude(@ipset.ip_network("fe80::%other/65"))
        .map(n => n.to_string())
        .to_array(),
        ["fe80::8000:0:0:0/65"],
      )
    }
  }
  let first = @ipset.ip_address("fe80::1%a")
  let same = @ipset.ip_address("fe80::1%b")
  let unscoped = @ipset.ip_address("fe80::1")
  for left in [first, same, unscoped] {
    for right in [first, same, unscoped] {
      assert_eq(
        @ipset.summarize_address_range(left, right).map(n => n.to_string()),
        ["fe80::1/128"],
      )
    }
  }
  assert_eq(
    @ipset.summarize_address_range(
      @ipset.ip_address("fe80::%b"),
      @ipset.ip_address("fe80::1%a"),
    ).map(n => n.to_string()),
    ["fe80::/127"],
  )
  assert_true(
    try {
      ignore(
        @ipset.summarize_address_range(first, @ipset.ip_address("fe80::%b")),
      )
      false
    } catch {
      @ipset.InvalidRange(_) => true
      _ => false
    },
  )
}

///|
test "compare networks is numeric while Compare preserves scoped identity" {
  let a = @ipset.ip_network("192.0.2.0/24")
  let b = @ipset.ip_network("192.0.2.0/25")
  let c = @ipset.ip_network("192.0.2.128/25")
  assert_eq(a.compare_networks(a), 0)
  assert_eq(a.compare_networks(b), -1)
  assert_eq(b.compare_networks(a), 1)
  assert_eq(b.compare_networks(c), -1)
  assert_eq(c.compare_networks(b), 1)
  let plain = @ipset.ip_network("fe80::/64")
  let narrow = @ipset.ip_network("fe80::/128")
  let scope_a = @ipset.ip_network("fe80::%a/64")
  let scope_b = @ipset.ip_network("fe80::%b/64")
  assert_true(plain < narrow && narrow < scope_a && scope_a < scope_b)
  for left in [plain, scope_a, scope_b] {
    for right in [plain, scope_a, scope_b] {
      assert_eq(left.compare_networks(right), 0)
    }
    assert_eq(left.compare_networks(narrow), -1)
    assert_eq(narrow.compare_networks(left), 1)
  }
  assert_true(
    @ipset.get_mixed_type_key(@ipset.NetworkInput(scope_a)) <
    @ipset.get_mixed_type_key(@ipset.NetworkInput(narrow)),
  )
  assert_true(a < plain)
  assert_true(
    try {
      ignore(a.compare_networks(plain))
      false
    } catch {
      @ipset.InvalidRange(_) => true
      _ => false
    },
  )
}
