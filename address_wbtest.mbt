///|
test "internal trailing zeros handles zero and each word boundary" {
  assert_eq(Address::parse("0.0.0.0").trailing_zeros(), 32)
  assert_eq(Address::parse("::").trailing_zeros(), 128)
  assert_eq(Address::parse("::1").trailing_zeros(), 0)
  assert_eq(Address::parse("::1:0:0").trailing_zeros(), 32)
  assert_eq(Address::parse("0:0:0:1::").trailing_zeros(), 64)
  assert_eq(Address::parse("0:1::").trailing_zeros(), 96)
  assert_eq(Address::parse("8000::").trailing_zeros(), 127)
}

///|
test "all mask bits and block ends match independent individual bit expectations" {
  let maximum = Address::parse("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
  let zero = Address::parse("::")
  for prefix = 0; prefix <= 128; prefix = prefix + 1 {
    let masked = maximum.mask(prefix)
    let ended = zero.block_end(prefix)
    let high = [masked.a, masked.b, masked.c, masked.d]
    let low = [ended.a, ended.b, ended.c, ended.d]
    for bit = 0; bit < 128; bit = bit + 1 {
      let word = bit / 32
      let shift = 31 - bit % 32
      assert_eq((high[word] >> shift) & 1U, if bit < prefix { 1U } else { 0U })
      assert_eq((low[word] >> shift) & 1U, if bit < prefix { 0U } else { 1U })
    }
  }
}
