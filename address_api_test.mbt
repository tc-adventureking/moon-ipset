///|
test "rich address text, packed bytes and exact integers round trip" {
  let cases = [
    ("0.0.0.0", 0N),
    ("192.0.2.1", 3221225985N),
    ("255.255.255.255", 4294967295N),
    ("::", 0N),
    ("2001:db8::1", 42540766411282592856903984951653826561N),
    (
      "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", 340282366920938463463374607431768211455N,
    ),
  ]
  for (text, numeric) in cases {
    let address = @ipset.ip_address(text)
    assert_eq(address.to_bigint(), numeric)
    assert_eq(@ipset.IpAddress::from_bytes(address.to_bytes()), address)
    assert_eq(
      @ipset.IpAddress::from_bigint(numeric, family=address.family()),
      address,
    )
    assert_eq(address.to_bytes().length(), address.max_prefixlen() / 8)
    assert_eq(address.compressed(), text)
  }
  assert_eq(@ipset.IpAddress::from_bigint(4294967295N).version(), 4)
  assert_eq(@ipset.IpAddress::from_bigint(4294967296N).version(), 6)
  assert_eq(@ipset.ipv4_address("127.0.0.1").version(), 4)
  assert_eq(@ipset.ipv6_address("::1").version(), 6)
}

///|
test "rich address scope identity and native total ordering" {
  let a = @ipset.ip_address("fe80::1%eth0")
  let b = @ipset.ip_address("fe80::1%eth1")
  let plain = @ipset.ip_address("fe80::1")
  assert_eq(a.scope_id(), Some("eth0"))
  assert_eq(a.to_string(), "fe80::1%eth0")
  assert_eq(a.exploded(), "fe80:0000:0000:0000:0000:0000:0000:0001%eth0")
  assert_true(a != b)
  assert_true(a != plain)
  assert_true(plain < a && a < b)
  assert_eq(a.unscoped(), plain)
  assert_eq(a.to_bigint(), plain.to_bigint())
  assert_eq(a.to_bytes(), plain.to_bytes())
  assert_eq(a.add(0N), plain)
  assert_eq(a.hash(), @ipset.ip_address("fe80::1%eth0").hash())
}

///|
test "scope round trips reject prefix separators but preserve valid zone text" {
  for scope in ["eth0", "12", "zone 1", "[eth]", "a:b", "🚀"] {
    let text = "fe80::1%\{scope}"
    let address = @ipset.ip_address(text)
    assert_eq(address.scope_id(), Some(scope))
    assert_eq(address.to_string(), text)
    assert_eq(@ipset.ip_address(address.to_string()), address)
    let interface = @ipset.IpInterface::from_address(address, 64)
    assert_eq(@ipset.ip_interface(interface.to_string()), interface)
    let singleton = @ipset.IpNetwork::from_address(address, 128)
    assert_eq(@ipset.ip_network(singleton.to_string()), singleton)
  }
  for
    text in [
      "fe80::1%eth/0", "fe80::1%/64", "fe80::1/64%eth0", "fe80::1%eth0/", "::1/128",
      "192.0.2.1/32", "fe80::1%%", "fe80::1%", "fe80::1%a%b",
    ] {
    assert_true(
      try {
        ignore(@ipset.ip_address(text))
        false
      } catch {
        @ipset.InvalidAddress(_) => true
        _ => false
      },
      msg=text,
    )
  }
}

///|
test "rich address rejects invalid scope, packed length and family range" {
  for
    text in [
      "fe80::1%", "fe80::1%a%b", "1.2.3.4%eth0", "[::1]", "::g", "01.2.3.4",
    ] {
    let rejected = try {
      let _ = @ipset.ip_address(text)
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=text)
  }
  for value in [-1N, 340282366920938463463374607431768211456N] {
    let rejected = try {
      let _ = @ipset.IpAddress::from_bigint(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_true(
    try {
      let _ = @ipset.IpAddress::from_bigint(4294967296N, family=@ipset.V4)
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @ipset.IpAddress::from_bytes(b"abc")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @ipset.ipv4_address("::1")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @ipset.ipv6_address("127.0.0.1")
      false
    } catch {
      _ => true
    },
  )
}

///|
test "rich address expanded, numeric formatting and PTR" {
  let a = @ipset.ip_address("192.0.2.1")
  assert_eq(a.exploded(), "192.0.2.1")
  assert_eq(a.reverse_pointer(), "1.2.0.192.in-addr.arpa")
  assert_eq(a.format("b"), "11000000000000000000001000000001")
  assert_eq(a.format("#_b"), "0b1100_0000_0000_0000_0000_0010_0000_0001")
  assert_eq(a.format("x"), "c0000201")
  assert_eq(a.format("#_X"), "0XC000_0201")
  assert_eq(a.format("n"), a.format("b"))
  assert_eq(a.format("s"), a.to_string())
  assert_eq(a.format(""), a.to_string())
  let b = @ipset.ip_address("2001:db8::1")
  assert_eq(b.exploded(), "2001:0db8:0000:0000:0000:0000:0000:0001")
  assert_eq(b.format("_X"), "2001_0DB8_0000_0000_0000_0000_0000_0001")
  assert_eq(
    b.reverse_pointer(),
    "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa",
  )
  for invalid in ["d", "#s", "__x", "x_", "_#x", "bb"] {
    assert_true(
      try {
        let _ = b.format(invalid)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "string address formatting supports width alignment fill and precision" {
  let a = @ipset.ip_address("192.0.2.1")
  let cases = [
    ("<20s", "192.0.2.1           "),
    (">40s", "                               192.0.2.1"),
    ("*^15s", "***192.0.2.1***"),
    ("*^14s", "**192.0.2.1***"),
    ("15s", "192.0.2.1      "),
    ("020s", "192.0.2.100000000000"),
    (">020s", "00000000000192.0.2.1"),
    ("*<020s", "192.0.2.1***********"),
    (".5s", "192.0"),
    (">12.5s", "       192.0"),
    ("010.4s", "192.000000"),
    ("00020s", "192.0.2.100000000000"),
    (".^s", "192.0.2.1"),
    ("0s", "192.0.2.1"),
    ("^0s", "192.0.2.1"),
    ("2s", "192.0.2.1"),
    (".0s", ""),
    (".2147483647s", "192.0.2.1"),
  ]
  for (spec, expected) in cases {
    assert_eq(a.format(spec), expected, msg=spec)
  }
  let scoped = @ipset.ip_address("fe80::1%🚀")
  assert_eq(scoped.format("🟦^12s"), "🟦fe80::1%🚀🟦🟦")
  assert_eq(scoped.format(">12.9s"), "   fe80::1%🚀")
  assert_eq(scoped.format(".8s"), "fe80::1%")
  assert_eq(
    @ipset.ip_address("::ffff:192.0.2.1").format("*>20s"),
    "****::ffff:192.0.2.1",
  )
  assert_eq(
    @ipset.ip_address("2001:db8::1").format("#n"),
    "0x20010db8000000000000000000000001",
  )
}

///|
test "address string format rejects unsupported flags malformed and overflowing widths" {
  let a = @ipset.ip_address("192.0.2.1")
  for
    spec in [
      "+20s", "=20s", "#20s", "_20s", ",20s", "20.s", ".s", "1.2.3s", "20", "20x",
      "-1s", "2147483648s", ".2147483648s", "٢s", "S",
    ] {
    assert_true(
      try {
        ignore(a.format(spec))
        false
      } catch {
        @ipset.InvalidAddress(_) => true
        _ => false
      },
      msg=spec,
    )
  }
}

///|
test "rich address checked arithmetic includes carry and overflow" {
  assert_eq(@ipset.ip_address("::ffff:ffff").add(1N).to_string(), "::1:0:0")
  assert_eq(
    @ipset.ip_address("::1:0:0").subtract(1N).to_string(),
    "::ffff:ffff",
  )
  assert_eq(@ipset.ip_address("10.0.0.0").add(-1N).to_string(), "9.255.255.255")
  for text in ["0.0.0.0", "::"] {
    assert_true(
      try {
        let _ = @ipset.ip_address(text).subtract(1N)
        false
      } catch {
        _ => true
      },
    )
  }
  for text in ["255.255.255.255", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"] {
    assert_true(
      try {
        let _ = @ipset.ip_address(text).add(1N)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "rich address mapped and transition extraction" {
  let mapped = @ipset.ip_address("::ffff:c000:201")
  assert_eq(mapped.to_string(), "::ffff:192.0.2.1")
  assert_eq(mapped.exploded(), "0000:0000:0000:0000:0000:ffff:192.0.2.1")
  assert_eq(mapped.ipv4_mapped(), Some(@ipset.ip_address("192.0.2.1")))
  assert_eq(@ipset.ip_address("192.0.2.1").ipv6_mapped(), Some(mapped))
  assert_eq(
    @ipset.ip_address("2002:c000:0201::").sixtofour(),
    Some(@ipset.ip_address("192.0.2.1")),
  )
  assert_eq(
    @ipset.ip_address("2001:0:4136:e378:8000:63bf:3fff:fdd2").teredo(),
    Some((@ipset.ip_address("65.54.227.120"), @ipset.ip_address("192.0.2.45"))),
  )
  assert_eq(@ipset.ip_address("2001:db8::").teredo(), None)
  assert_eq(@ipset.ip_address("192.0.2.1").ipv4_mapped(), None)
  assert_eq(@ipset.ip_address("2001:db8::").sixtofour(), None)
}

///|
test "rich address classifications include special use and exceptions" {
  for
    text in [
      "10.0.0.1", "192.0.2.1", "192.0.0.8", "192.0.0.11", "3fff::1", "64:ff9b:1::1",
      "2002::1", "2001:1::3",
    ] {
    let a = @ipset.ip_address(text)
    assert_true(a.is_private(), msg=text)
    assert_false(a.is_global(), msg=text)
  }
  for
    text in [
      "8.8.8.8", "192.0.0.9", "192.0.0.10", "2001:1::1", "2001:1::2", "2001:3::1",
      "2001:4:112::1", "2001:20::1", "2001:30::1", "2606:4700::1111",
    ] {
    let a = @ipset.ip_address(text)
    assert_false(a.is_private(), msg=text)
    assert_true(a.is_global(), msg=text)
  }
  for text in ["100.64.0.0", "100.127.255.255", "::ffff:100.64.0.1"] {
    let a = @ipset.ip_address(text)
    assert_false(a.is_private())
    assert_false(a.is_global())
  }
  assert_true(@ipset.ip_address("127.255.0.1").is_loopback())
  assert_true(@ipset.ip_address("::1").is_loopback())
  assert_true(@ipset.ip_address("169.254.0.1").is_link_local())
  assert_true(@ipset.ip_address("febf::1").is_link_local())
  assert_false(@ipset.ip_address("fec0::1").is_link_local())
  assert_true(@ipset.ip_address("fec0::1").is_site_local())
  assert_true(@ipset.ip_address("239.255.255.255").is_multicast())
  assert_true(@ipset.ip_address("ff02::1").is_multicast())
  assert_true(@ipset.ip_address("240.0.0.0").is_reserved())
  assert_false(@ipset.ip_address("2001:db8::1").is_reserved())
  assert_true(@ipset.ip_address("0.0.0.0").is_unspecified())
  assert_true(@ipset.ip_address("::").is_unspecified())
}

///|
test "rich address mapped classifiers follow embedded IPv4" {
  for
    text in [
      "0.0.0.0", "127.0.0.1", "169.254.1.2", "224.0.0.1", "240.0.0.1", "8.8.8.8",
      "100.64.0.1", "192.0.0.9",
    ] {
    let a = @ipset.ip_address(text)
    let mapped = @ipset.ip_address("::ffff:\{text}")
    assert_eq(mapped.is_private(), a.is_private())
    assert_eq(mapped.is_global(), a.is_global())
    assert_eq(mapped.is_reserved(), a.is_reserved())
    assert_eq(mapped.is_loopback(), a.is_loopback())
    assert_eq(mapped.is_multicast(), a.is_multicast())
    assert_eq(mapped.is_link_local(), a.is_link_local())
    assert_eq(mapped.is_unspecified(), a.is_unspecified())
  }
}

///|
test "rich address hash equality preserves address family and scope" {
  let plain = @ipset.ip_address("fe80::1")
  let scoped = @ipset.ip_address("fe80::1%eth0")
  let other_scope = @ipset.ip_address("fe80::1%eth1")
  let values : Map[@ipset.IpAddress, Int32] = Map([])
  values[plain] = 1
  values[scoped] = 2
  values[other_scope] = 3
  values[@ipset.ip_address("0.0.0.0")] = 4
  values[@ipset.ip_address("::")] = 5
  assert_eq(values.length(), 5)
  assert_eq(values[@ipset.IpAddress::from_bytes(plain.to_bytes())], 1)
  assert_eq(values[@ipset.ip_address("fe80:0:0:0:0:0:0:1%eth0")], 2)
  assert_eq(values[@ipset.ip_address("fe80::1%eth1")], 3)
  assert_eq(values[@ipset.IpAddress::from_bigint(0N)], 4)
  assert_eq(values[@ipset.IpAddress::from_bigint(0N, family=@ipset.V6)], 5)
}

///|
test "rich address fixed-family packed helpers and signed offsets" {
  assert_eq(@ipset.v4_int_to_packed(1N), b"\x00\x00\x00\x01")
  let last = (1N << 128) - 1N
  assert_eq(
    @ipset.v6_int_to_packed(last),
    b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff",
  )
  assert_true(
    try {
      let _ = @ipset.v4_int_to_packed(1N << 32)
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @ipset.v6_int_to_packed(-1N)
      false
    } catch {
      _ => true
    },
  )
  let a = @ipset.ip_address("::2%zone")
  assert_eq(a.subtract(-1N).to_string(), "::3")
  assert_eq(a.subtract(2N).to_string(), "::")
  assert_true(
    try {
      let _ = a.subtract(3N)
      false
    } catch {
      _ => true
    },
  )
  assert_eq(a.reverse_pointer(), a.unscoped().reverse_pointer())
}
