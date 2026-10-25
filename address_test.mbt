///|
test "IPv4 strict parse and unsigned ordering" {
  for text in ["0.0.0.0", "127.255.255.255", "128.0.0.0", "255.255.255.255"] {
    let address = @ipset.Address::parse(text)
    assert_eq(address.to_string(), text)
    assert_true(address.family() == @ipset.Family::V4)
    assert_eq(address.width(), 32)
  }
  assert_true(
    @ipset.Address::parse("127.255.255.255") <
    @ipset.Address::parse("128.0.0.0"),
  )
  assert_true(
    @ipset.Address::parse("255.255.255.255") < @ipset.Address::parse("::"),
  )
}

///|
test "IPv6 canonical compression and embedded IPv4" {
  let examples = [
    ("0:0:0:0:0:0:0:0", "::"),
    ("0:0:0:0:0:0:0:1", "::1"),
    ("2001:0DB8:0000:0000:0000:0000:0000:0001", "2001:db8::1"),
    ("1:0:0:2:0:0:3:4", "1::2:0:0:3:4"),
    ("1:2:3:4:5:6:0:8", "1:2:3:4:5:6:0:8"),
    ("1:2:3:4:5:6:0:0", "1:2:3:4:5:6::"),
    ("::ffff:192.0.2.1", "::ffff:c000:201"),
    ("1:2:3:4:5:6:192.0.2.1", "1:2:3:4:5:6:c000:201"),
  ]
  for item in examples {
    let address = @ipset.Address::parse(item.0)
    assert_eq(address.to_string(), item.1)
    assert_true(address.family() == @ipset.Family::V6)
    assert_eq(address.width(), 128)
    assert_true(@ipset.Address::parse(item.1) == address)
  }
}

///|
test "IPv4 and IPv6 domain limits never wrap" {
  for text in ["0.0.0.0", "::"] {
    let address = @ipset.Address::parse(text)
    assert_true(address.previous() == None)
    match address.next() {
      Some(next) => assert_true(next.previous() == Some(address))
      None => fail("zero must have successor")
    }
  }
  for text in ["255.255.255.255", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"] {
    let address = @ipset.Address::parse(text)
    assert_true(address.next() == None)
    match address.previous() {
      Some(previous) => assert_true(previous.next() == Some(address))
      None => fail("maximum must have predecessor")
    }
  }
}

///|
test "IPv6 carry and borrow across every 32 bit word boundary" {
  let boundaries = [
    ("::ffff:ffff", "::1:0:0"),
    ("::ffff:ffff:ffff:ffff", "0:0:0:1::"),
    ("0:0:ffff:ffff:ffff:ffff:ffff:ffff", "0:1::"),
  ]
  for boundary in boundaries {
    let low = @ipset.Address::parse(boundary.0)
    let high = @ipset.Address::parse(boundary.1)
    assert_true(low.next() == Some(high))
    assert_true(high.previous() == Some(low))
    assert_true(low < high)
  }
}

///|
test "malformed addresses are rejected" {
  let invalid = [
    "", "1.2.3", "1.2.3.4.5", "01.2.3.4", "256.1.1.1", "1..1.1", "+1.2.3.4", "1.2.3.4 ",
    " 1.2.3.4", "1.2.3.4/32", ":", ":::1", "1::2::3", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9",
    "1:2:3:4:5:6:7:8::", "::1:2:3:4:5:6:7:8", "12345::", "g::", "[::1]", "fe80::1%eth0",
    "::1 ", "1.2.3.4::", "::ffff:01.2.3.4", "::ffff:256.2.3.4", "1:2:3:4:5:192.0.2.1",
    "::ffff:192.0.2.1:",
  ]
  for text in invalid {
    let rejected = try {
      let _ = @ipset.Address::parse(text)
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg="accepted invalid address: \{text}")
  }
}

///|
test "CIDR normalizes or rejects host bits according to strict flag" {
  assert_eq(@ipset.Cidr::parse("192.0.2.129/24").to_string(), "192.0.2.0/24")
  assert_eq(@ipset.Cidr::parse("2001:db8::1/64").to_string(), "2001:db8::/64")
  assert_eq(
    @ipset.Cidr::parse("::ffff:192.0.2.1/120").to_string(),
    "::ffff:c000:200/120",
  )
  for text in ["192.0.2.1/24", "2001:db8::1/64"] {
    let rejected = try {
      let _ = @ipset.Cidr::parse(text, strict=true)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_eq(@ipset.Cidr::parse("192.0.2.0/24", strict=true).prefix(), 24)
}

///|
test "CIDR rejects invalid lengths and malformed prefixes" {
  for
    text in [
      "::/129", "1.2.3.4/33", "::/-1", "::/+1", "::/01", "::/00", "::/", "::/1/2",
      "::/1 ", "::/６４", "::",
    ] {
    let rejected = try {
      let _ = @ipset.Cidr::parse(text)
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg="accepted invalid CIDR: \{text}")
  }
  for prefix in [-1, 33, 128] {
    let rejected = try {
      let _ = @ipset.Cidr::new(@ipset.Address::parse("1.2.3.4"), prefix)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "all CIDR prefix lengths preserve boundaries and roundtrip" {
  for
    text in [
      "0.0.0.0", "255.255.255.255", "192.168.123.251", "::", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
      "abcd:1234:5678:9abc:def0:1357:2468:9876",
    ] {
    let address = @ipset.Address::parse(text)
    for prefix = 0; prefix <= address.width(); prefix = prefix + 1 {
      let cidr = @ipset.Cidr::new(address, prefix)
      assert_true(cidr.network() <= address)
      assert_true(address <= cidr.last())
      assert_true(cidr.network().family() == address.family())
      assert_true(cidr.last().family() == address.family())
      assert_true(@ipset.Cidr::parse(cidr.to_string(), strict=true) == cidr)
      assert_true(@ipset.Cidr::new(cidr.last(), prefix) == cidr)
      if prefix == address.width() {
        assert_true(cidr.network() == address)
        assert_true(cidr.last() == address)
      }
    }
  }
}
