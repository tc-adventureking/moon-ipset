///|
test "mixed type key orders hosts networks and address families" {
  let items = [
    @ipset.NetworkInput(@ipset.ip_network("192.0.2.0/26")),
    @ipset.AddressInput(@ipset.ip_address("::")),
    @ipset.NetworkInput(@ipset.ip_network("192.0.2.0/25")),
    @ipset.AddressInput(@ipset.ip_address("192.0.2.0")),
    @ipset.NetworkInput(@ipset.ip_network("192.0.2.0/24")),
    @ipset.AddressInput(@ipset.ip_address("192.0.2.1")),
  ]
  items.sort_by(fn(a, b) {
    @ipset.get_mixed_type_key(a).compare(@ipset.get_mixed_type_key(b))
  })
  assert_eq(items.map(fn(item) { item.to_string() }), [
    "192.0.2.0", "192.0.2.0/24", "192.0.2.0/25", "192.0.2.0/26", "192.0.2.1", "::",
  ])
  assert_eq(
    @ipset.get_mixed_type_key(
      @ipset.AddressInput(@ipset.ip_address("fe80::1%a")),
    ),
    @ipset.get_mixed_type_key(
      @ipset.AddressInput(@ipset.ip_address("fe80::1%b")),
    ),
  )
}

///|
test "mixed collapse merges host addresses and overlapping networks" {
  let inputs = [
    @ipset.AddressInput(@ipset.ip_address("192.0.2.1")),
    @ipset.NetworkInput(@ipset.ip_network("192.0.2.0/31")),
    @ipset.AddressInput(@ipset.ip_address("192.0.2.2")),
    @ipset.AddressInput(@ipset.ip_address("192.0.2.3")),
  ]
  assert_eq(@ipset.collapse_ip_inputs(inputs).map(fn(n) { n.to_string() }), [
    "192.0.2.0/30",
  ])
  let v6 = [
    @ipset.AddressInput(@ipset.ip_address("2001:db8::")),
    @ipset.AddressInput(@ipset.ip_address("2001:db8::1")),
    @ipset.NetworkInput(@ipset.ip_network("2001:db8::2/127")),
  ]
  assert_eq(@ipset.collapse_ip_inputs(v6).map(fn(n) { n.to_string() }), [
    "2001:db8::/126",
  ])
  assert_true(@ipset.collapse_ip_inputs([]).is_empty())
}

///|
test "mixed collapse rejects cross-family combinations" {
  let combinations = [
    [
      @ipset.AddressInput(@ipset.ip_address("0.0.0.0")),
      @ipset.AddressInput(@ipset.ip_address("::")),
    ],
    [
      @ipset.AddressInput(@ipset.ip_address("0.0.0.0")),
      @ipset.NetworkInput(@ipset.ip_network("::/0")),
    ],
    [
      @ipset.NetworkInput(@ipset.ip_network("0.0.0.0/0")),
      @ipset.AddressInput(@ipset.ip_address("::")),
    ],
  ]
  for inputs in combinations {
    assert_true(
      try {
        let _ = @ipset.collapse_ip_inputs(inputs)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "mixed collapse uses an explicit numeric scope policy" {
  let hosts = [
    @ipset.AddressInput(@ipset.ip_address("fe80::1%eth0")),
    @ipset.AddressInput(@ipset.ip_address("fe80::1%eth1")),
  ]
  assert_eq(@ipset.collapse_ip_inputs(hosts).map(fn(n) { n.to_string() }), [
    "fe80::1/128",
  ])
  let scoped_network = [
    @ipset.NetworkInput(@ipset.ip_network("fe80::%eth0/64")),
  ]
  assert_eq(
    @ipset.collapse_ip_inputs(scoped_network).map(fn(n) { n.to_string() }),
    ["fe80::/64"],
  )
}

///|
test "interface mixed keys use host value and preserve interface display" {
  let interface = @ipset.InterfaceInput(@ipset.ip_interface("192.0.2.1/24"))
  assert_eq(interface.to_string(), "192.0.2.1/24")
  assert_eq(
    @ipset.get_mixed_type_key(interface),
    @ipset.get_mixed_type_key(
      @ipset.AddressInput(@ipset.ip_address("192.0.2.1")),
    ),
  )
  assert_eq(
    @ipset.get_mixed_type_key(
      @ipset.InterfaceInput(@ipset.ip_interface("fe80::1%eth0/64")),
    ),
    @ipset.get_mixed_type_key(
      @ipset.AddressInput(@ipset.ip_address("fe80::1%eth1")),
    ),
  )
  let inputs = [
    @ipset.NetworkInput(@ipset.ip_network("192.0.2.0/24")),
    @ipset.InterfaceInput(@ipset.ip_interface("192.0.2.2/16")),
    @ipset.AddressInput(@ipset.ip_address("192.0.2.0")),
    interface,
    @ipset.InterfaceInput(@ipset.ip_interface("::/0")),
  ]
  inputs.sort_by(fn(a, b) {
    @ipset.get_mixed_type_key(a).compare(@ipset.get_mixed_type_key(b))
  })
  assert_eq(inputs.map(fn(item) { item.to_string() }), [
    "192.0.2.0", "192.0.2.0/24", "192.0.2.1/24", "192.0.2.2/16", "::/0",
  ])
}

///|
test "mixed collapse treats interfaces as hosts rather than their subnets" {
  assert_eq(
    @ipset.collapse_ip_inputs([
      @ipset.InterfaceInput(@ipset.ip_interface("192.0.2.1/24")),
    ]).map(fn(n) { n.to_string() }),
    ["192.0.2.1/32"],
  )
  assert_eq(
    @ipset.collapse_ip_inputs([
      @ipset.InterfaceInput(@ipset.ip_interface("192.0.2.1/24")),
      @ipset.AddressInput(@ipset.ip_address("192.0.2.0")),
      @ipset.NetworkInput(@ipset.ip_network("192.0.2.2/31")),
    ]).map(fn(n) { n.to_string() }),
    ["192.0.2.0/30"],
  )
  assert_eq(
    @ipset.collapse_ip_inputs([
      @ipset.InterfaceInput(@ipset.ip_interface("fe80::%eth0/64")),
      @ipset.InterfaceInput(@ipset.ip_interface("fe80::1%eth1/64")),
    ]).map(fn(n) { n.to_string() }),
    ["fe80::/127"],
  )
  let mixed = [
    [
      @ipset.InterfaceInput(@ipset.ip_interface("192.0.2.1/24")),
      @ipset.InterfaceInput(@ipset.ip_interface("::1/64")),
    ],
    [
      @ipset.InterfaceInput(@ipset.ip_interface("192.0.2.1/24")),
      @ipset.NetworkInput(@ipset.ip_network("::/0")),
    ],
    [
      @ipset.InterfaceInput(@ipset.ip_interface("::1/64")),
      @ipset.AddressInput(@ipset.ip_address("192.0.2.1")),
    ],
  ]
  for inputs in mixed {
    assert_true(
      try {
        ignore(@ipset.collapse_ip_inputs(inputs))
        false
      } catch {
        @ipset.InvalidRange(_) => true
        _ => false
      },
    )
  }
}
