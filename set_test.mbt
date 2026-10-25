///|
fn cidr_texts(set : @ipset.IpSet) -> Array[String] {
  set.cidrs().map(cidr => cidr.to_string())
}

///|
test "empty set identities" {
  let empty = @ipset.IpSet::empty()
  let a = @ipset.IpSet::from_cidrs(["192.0.2.0/24", "2001:db8::/32"])
  assert_true(empty.is_empty())
  assert_eq(cidr_texts(a.union(empty)), cidr_texts(a))
  assert_eq(cidr_texts(empty.union(a)), cidr_texts(a))
  assert_true(a.intersection(empty).is_empty())
  assert_true(empty.difference(a).is_empty())
  assert_eq(cidr_texts(a.difference(empty)), cidr_texts(a))
  assert_true(a.difference(a).is_empty())
  assert_true(empty.is_subset_of(a))
  assert_false(empty.overlaps(a))
}

///|
test "normalize duplicates nested networks and adjacent halves" {
  let set = @ipset.IpSet::from_cidrs([
    "192.0.2.128/25", "192.0.2.1/25", "192.0.2.64/26", "192.0.2.1/25", "2001:db8::/33",
    "2001:db8:8000::/33",
  ])
  assert_eq(cidr_texts(set), ["192.0.2.0/24", "2001:db8::/32"])
  assert_eq(set.intervals().length(), 2)
}

///|
test "unsigned IPv4 sorting and full-family normalization" {
  let set = @ipset.IpSet::from_cidrs([
    "255.255.255.255/32", "128.0.0.0/1", "0.0.0.0/1", "8000::/1", "::/1", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128",
  ])
  assert_eq(cidr_texts(set), ["0.0.0.0/0", "::/0"])
  assert_true(set.contains(@ipset.Address::parse("255.255.255.255")))
  assert_true(
    set.contains(
      @ipset.Address::parse("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
    ),
  )
}

///|
test "family isolation including mapped IPv6" {
  let ipv4 = @ipset.IpSet::from_cidrs(["192.0.2.0/24"])
  let mapped = @ipset.IpSet::from_cidrs(["::ffff:192.0.2.0/120"])
  assert_true(ipv4.intersection(mapped).is_empty())
  assert_false(ipv4.overlaps(mapped))
  assert_false(ipv4.contains(@ipset.Address::parse("::ffff:192.0.2.1")))
  assert_false(mapped.contains(@ipset.Address::parse("192.0.2.1")))
  assert_eq(cidr_texts(ipv4.union(mapped)), [
    "192.0.2.0/24", "::ffff:c000:200/120",
  ])
  assert_eq(cidr_texts(ipv4.difference(mapped)), ["192.0.2.0/24"])
}

///|
test "difference splits interior excludes and preserves operands" {
  let all = @ipset.IpSet::from_cidrs(["192.0.2.0/24", "2001:db8::/120"])
  let excluded = @ipset.IpSet::from_cidrs([
    "192.0.2.32/27", "192.0.2.128/26", "2001:db8::40/122",
  ])
  let remaining = all.difference(excluded)
  assert_eq(cidr_texts(remaining), [
    "192.0.2.0/27", "192.0.2.64/26", "192.0.2.192/26", "2001:db8::/122", "2001:db8::80/121",
  ])
  assert_eq(cidr_texts(remaining.union(excluded)), cidr_texts(all))
  assert_true(remaining.intersection(excluded).is_empty())
  assert_eq(cidr_texts(all), ["192.0.2.0/24", "2001:db8::/120"])
}

///|
test "one exclusion spanning several source intervals is retained" {
  let source = @ipset.IpSet::from_cidrs([
    "192.0.2.0/26", "192.0.2.128/26", "192.0.3.0/24",
  ])
  let excluded = @ipset.IpSet::from_cidrs(["192.0.2.0/24"])
  assert_eq(cidr_texts(source.difference(excluded)), ["192.0.3.0/24"])
}

///|
test "endpoint exclusions never wrap and full spaces stay compact" {
  let v4 = @ipset.IpSet::from_cidrs(["0.0.0.0/0"])
  let v4max = @ipset.IpSet::from_cidrs(["255.255.255.255/32"])
  let v4rest = cidr_texts(v4.difference(v4max))
  assert_eq(v4rest.length(), 32)
  assert_eq(v4rest[0], "0.0.0.0/1")
  assert_eq(v4rest[31], "255.255.255.254/32")
  let v6 = @ipset.IpSet::from_cidrs(["::/0"])
  let zero = @ipset.IpSet::from_cidrs(["::/128"])
  let v6rest = cidr_texts(v6.difference(zero))
  assert_eq(v6rest.length(), 128)
  assert_eq(v6rest[0], "::1/128")
  assert_eq(v6rest[127], "8000::/1")
  assert_true(v6.difference(v6).is_empty())
  assert_eq(cidr_texts(v4.union(v6)), ["0.0.0.0/0", "::/0"])
}

///|
test "inclusive range minimal cover" {
  let range = @ipset.Interval::new(
    @ipset.Address::parse("192.0.2.5"),
    @ipset.Address::parse("192.0.2.14"),
  )
  let set = @ipset.IpSet::from_ranges([range])
  assert_eq(cidr_texts(set), [
    "192.0.2.5/32", "192.0.2.6/31", "192.0.2.8/30", "192.0.2.12/31", "192.0.2.14/32",
  ])
  assert_true(set.contains(range.first()))
  assert_true(set.contains(range.last()))
  assert_false(set.contains(@ipset.Address::parse("192.0.2.4")))
  assert_false(set.contains(@ipset.Address::parse("192.0.2.15")))
}

///|
test "adjacency across a 32-bit carry remains one interval" {
  let set = @ipset.IpSet::from_cidrs(["::ffff:ffff/128", "::1:0:0/128"])
  assert_eq(set.intervals().length(), 1)
  assert_eq(cidr_texts(set), ["::ffff:ffff/128", "::1:0:0/128"])
  let first = @ipset.IpSet::from_cidrs(["::ffff:ffff/128"])
  assert_eq(cidr_texts(set.difference(first)), ["::1:0:0/128"])
  let second = @ipset.IpSet::from_cidrs(["::1:0:0/128"])
  assert_eq(cidr_texts(set.difference(second)), ["::ffff:ffff/128"])
}

///|
test "range arrays cannot mutate an existing set" {
  let first = @ipset.Interval::new(
    @ipset.Address::parse("192.0.2.0"),
    @ipset.Address::parse("192.0.2.127"),
  )
  let second = @ipset.Interval::new(
    @ipset.Address::parse("192.0.2.128"),
    @ipset.Address::parse("192.0.2.255"),
  )
  let input = [first]
  let set = @ipset.IpSet::from_ranges(input)
  input[0] = second
  input.push(second)
  assert_eq(cidr_texts(set), ["192.0.2.0/25"])
  let returned = set.intervals()
  returned.clear()
  returned.push(second)
  assert_eq(cidr_texts(set), ["192.0.2.0/25"])
  assert_eq(cidr_texts(@ipset.IpSet::from_ranges([second, first])), [
    "192.0.2.0/24",
  ])
}

///|
test "invalid ranges and CIDRs are rejected atomically" {
  let a = @ipset.Address::parse("192.0.2.1")
  let b = @ipset.Address::parse("192.0.2.0")
  let c = @ipset.Address::parse("::1")
  let reversed_rejected = try {
    let _ = @ipset.Interval::new(a, b)
    false
  } catch {
    _ => true
  }
  let mixed_rejected = try {
    let _ = @ipset.Interval::new(a, c)
    false
  } catch {
    _ => true
  }
  let invalid_rejected = try {
    let _ = @ipset.IpSet::from_cidrs(["192.0.2.0/24", "bad"])
    false
  } catch {
    _ => true
  }
  assert_true(reversed_rejected && mixed_rejected && invalid_rejected)
}

///|
fn membership_mask(
  set : @ipset.IpSet,
  addresses : Array[@ipset.Address],
) -> Int32 {
  let mut result = 0
  for i = 0; i < addresses.length(); i = i + 1 {
    if set.contains(addresses[i]) {
      result = result | (1 << i)
    }
  }
  result
}

///|
fn is_canonical(set : @ipset.IpSet) -> Bool {
  let intervals = set.intervals()
  for i = 0; i < intervals.length(); i = i + 1 {
    let current = intervals[i]
    if current.first().family() != current.last().family() ||
      current.first() > current.last() {
      return false
    }
    if i > 0 {
      let previous = intervals[i - 1]
      if previous.last() >= current.first() {
        return false
      }
      if previous.first().family() == current.first().family() {
        match previous.last().next() {
          Some(next) => if next == current.first() { return false }
          None => ()
        }
      }
    }
  }
  true
}

///|
test "exhaustive eight-address sets against bitmask oracle in both families" {
  for base in ["198.51.100.", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:fff"] {
    let addresses = []
    for i = 0; i < 8; i = i + 1 {
      addresses.push(@ipset.Address::parse(base + i.to_string()))
    }
    let sets = []
    for mask = 0; mask < 256; mask = mask + 1 {
      let ranges = []
      for i = 0; i < 8; i = i + 1 {
        if (mask & (1 << i)) != 0 {
          ranges.push(@ipset.Interval::new(addresses[i], addresses[i]))
        }
      }
      sets.push(@ipset.IpSet::from_ranges(ranges))
    }
    for a = 0; a < 256; a = a + 1 {
      for b = 0; b < 256; b = b + 1 {
        let union = sets[a].union(sets[b])
        let intersection = sets[a].intersection(sets[b])
        let difference = sets[a].difference(sets[b])
        let symmetric = sets[a].symmetric_difference(sets[b])
        assert_eq(membership_mask(union, addresses), a | b)
        assert_eq(membership_mask(intersection, addresses), a & b)
        assert_eq(membership_mask(difference, addresses), a & (255 ^ b))
        assert_eq(membership_mask(symmetric, addresses), a ^ b)
        assert_eq(sets[a].is_subset_of(sets[b]), (a & b) == a)
        assert_eq(sets[a].overlaps(sets[b]), (a & b) != 0)
        assert_true(
          is_canonical(union) &&
          is_canonical(intersection) &&
          is_canonical(difference) &&
          is_canonical(symmetric),
        )
      }
    }
  }
}
