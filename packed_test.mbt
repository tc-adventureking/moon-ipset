///|
test "packed conversion agrees with exact integers for every byte position" {
  // Test both sparse and dense inputs. Checking through BigInt independently
  // detects byte-order errors that a matching encoder/decoder could conceal.
  for width in [4, 16] {
    let family = if width == 4 { @ipset.V4 } else { @ipset.V6 }
    for background in [0, 255] {
      for position = 0; position < width; position = position + 1 {
        for value = 0; value < 256; value = value + 1 {
          let bytes = Bytes::makei(width, i => {
            (if i == position { value } else { background }).to_byte()
          })
          let numeric = @bigint.BigInt::from_octets(bytes[:])
          let address = @ipset.IpAddress::from_bytes(bytes)
          assert_true(address.family() == family)
          assert_eq(address.to_bigint(), numeric)
          assert_eq(address.to_bytes(), bytes)
          assert_eq(
            @ipset.IpAddress::from_bigint(numeric, family~).to_bytes(),
            bytes,
          )
        }
      }
    }
  }
}

///|
test "packed conversion retains mixed words, leading zeros and numeric scope" {
  let mut state = 0x5eed2026U
  for width in [4, 16] {
    for _ in 0..<512 {
      let bytes = Bytes::makei(width, _ => {
        state = state * 1664525U + 1013904223U
        (state >> 24).to_byte()
      })
      let address = @ipset.IpAddress::from_bytes(bytes)
      assert_eq(address.to_bigint(), @bigint.BigInt::from_octets(bytes[:]))
      assert_eq(address.to_bytes(), bytes)
    }
  }
  let v6 = @ipset.IpAddress::from_bytes(
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xC0\x00\x02\x01",
  )
  assert_true(v6.family() == @ipset.V6)
  assert_eq(v6.to_string(), "::c000:201")
  let scoped = @ipset.ip_address("fe80::1234%eth0")
  let decoded = @ipset.IpAddress::from_bytes(scoped.to_bytes())
  assert_eq(decoded, scoped.unscoped())
  assert_eq(decoded.scope_id(), None)
}

///|
test "packed constructors reject invalid lengths with IpError" {
  for length in 0..<34 {
    if length == 4 || length == 16 {
      continue
    }
    let bytes = Bytes::make(length, b'\x80')
    assert_true(
      try {
        ignore(@ipset.IpAddress::from_bytes(bytes))
        false
      } catch {
        @ipset.InvalidAddress(_) => true
        _ => false
      },
    )
  }
}
