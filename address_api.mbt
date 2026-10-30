///|
/// A general IP address with an optional IPv6 zone identifier.
/// Legacy Address remains an unscoped numeric address for set algebra.
struct IpAddress {
  address_ : Address
  scope_ : String?
} derive(Eq)

///|
pub extend IpAddress with Eq::{equal, not_equal}

///|
pub extend IpAddress with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend IpAddress with Hash::{hash, hash_combine}

///|
pub extend IpAddress with Show::{output}

///|
pub extend IpAddress with @debug.Debug::{to_repr}

///|
pub fn ip_address(text : String) -> IpAddress raise IpError {
  IpAddress::parse(text)
}

///|
pub fn ipv4_address(text : String) -> IpAddress raise IpError {
  let result = IpAddress::parse(text)
  if result.family() != V4 {
    raise InvalidAddress(text)
  }
  result
}

///|
pub fn ipv6_address(text : String) -> IpAddress raise IpError {
  let result = IpAddress::parse(text)
  if result.family() != V6 {
    raise InvalidAddress(text)
  }
  result
}

///|
pub fn v4_int_to_packed(value : @bigint.BigInt) -> Bytes raise IpError {
  IpAddress::from_bigint(value, family=V4).to_bytes()
}

///|
pub fn v6_int_to_packed(value : @bigint.BigInt) -> Bytes raise IpError {
  IpAddress::from_bigint(value, family=V6).to_bytes()
}

///|
pub fn IpAddress::parse(text : String) -> IpAddress raise IpError {
  if text.contains("/") {
    raise InvalidAddress(text)
  }
  match text.split_once("%") {
    None => IpAddress::from_address(Address::parse(text))
    Some((numeric, scope)) => {
      if scope.is_empty() || scope.contains("%") || !numeric.contains(":") {
        raise InvalidAddress(text)
      }
      {
        address_: Address::parse(numeric.to_owned()),
        scope_: Some(scope.to_owned()),
      }
    }
  }
}

///|
pub fn IpAddress::from_address(address : Address) -> IpAddress {
  { address_: address, scope_: None, }
}

///|
pub fn IpAddress::as_address(self : IpAddress) -> Address {
  self.address_
}

///|
pub fn IpAddress::unscoped(self : IpAddress) -> IpAddress {
  IpAddress::from_address(self.address_)
}

///|
pub fn IpAddress::from_bigint(
  value : @bigint.BigInt,
  family? : Family,
) -> IpAddress raise IpError {
  let family = family.unwrap_or_else(fn() {
    if value < 1N << 32 {
      V4
    } else {
      V6
    }
  })
  let width = if family == V4 { 32 } else { 128 }
  if value < 0N || value >= 1N << width {
    raise InvalidAddress(value.to_string())
  }
  let mask = 4294967295N
  IpAddress::from_address({
    family_: family,
    a: ((value >> 96) & mask).to_uint(),
    b: ((value >> 64) & mask).to_uint(),
    c: ((value >> 32) & mask).to_uint(),
    d: (value & mask).to_uint(),
  })
}

///|
pub fn IpAddress::from_bytes(value : Bytes) -> IpAddress raise IpError {
  // Exact-width patterns read unsigned words in network byte order.
  let address = match value {
    [u32be(d)] => { family_: V4, a: 0U, b: 0U, c: 0U, d, }
    [u32be(a), u32be(b), u32be(c), u32be(d)] => { family_: V6, a, b, c, d, }
    _ => raise InvalidAddress("packed address must contain 4 or 16 bytes")
  }
  IpAddress::from_address(address)
}

///|
pub fn IpAddress::to_bigint(self : IpAddress) -> @bigint.BigInt {
  let a = self.address_
  (@bigint.BigInt::from_uint(a.a) << 96) |
  (@bigint.BigInt::from_uint(a.b) << 64) |
  (@bigint.BigInt::from_uint(a.c) << 32) |
  @bigint.BigInt::from_uint(a.d)
}

///|
pub fn IpAddress::to_bytes(self : IpAddress) -> Bytes {
  let address = self.address_
  if address.family_ == V4 {
    Bytes::makei(4, i => (address.d >> ((3 - i) * 8)).to_byte())
  } else {
    Bytes::makei(16, i => {
      let word = match i / 4 {
        0 => address.a
        1 => address.b
        2 => address.c
        _ => address.d
      }
      (word >> ((3 - i % 4) * 8)).to_byte()
    })
  }
}

///|
pub fn IpAddress::family(self : IpAddress) -> Family {
  self.address_.family()
}

///|
pub fn IpAddress::version(self : IpAddress) -> Int32 {
  if self.family() == V4 {
    4
  } else {
    6
  }
}

///|
pub fn IpAddress::max_prefixlen(self : IpAddress) -> Int32 {
  self.address_.width()
}

///|
pub fn IpAddress::scope_id(self : IpAddress) -> String? {
  self.scope_
}

///|
pub fn IpAddress::to_string(self : IpAddress) -> String {
  let numeric = match self.ipv4_mapped() {
    Some(v4) => "::ffff:\{v4.to_string()}"
    None => self.address_.to_string()
  }
  match self.scope_ {
    None => numeric
    Some(scope) => "\{numeric}%\{scope}"
  }
}

///|
pub fn IpAddress::compressed(self : IpAddress) -> String {
  self.to_string()
}

///|
fn ip_padded(text : String, width : Int32) -> String {
  "0".repeat(width - text.length()) + text
}

///|
pub fn IpAddress::exploded(self : IpAddress) -> String {
  if self.family() == V4 {
    return self.to_string()
  }
  match self.ipv4_mapped() {
    Some(v4) => {
      let numeric = "0000:0000:0000:0000:0000:ffff:\{v4.to_string()}"
      return match self.scope_ {
        None => numeric
        Some(scope) => "\{numeric}%\{scope}"
      }
    }
    None => ()
  }
  let a = self.address_
  let groups = [
    a.a >> 16,
    a.a & 65535U,
    a.b >> 16,
    a.b & 65535U,
    a.c >> 16,
    a.c & 65535U,
    a.d >> 16,
    a.d & 65535U,
  ]
  let numeric = groups
    .map(fn(g) { ip_padded(g.to_string(radix=16), 4) })
    .join(":")
  match self.scope_ {
    None => numeric
    Some(scope) => "\{numeric}%\{scope}"
  }
}

///|
/// The numeric PTR name. IPv6 zone identifiers do not enter DNS names.
pub fn IpAddress::reverse_pointer(self : IpAddress) -> String {
  if self.family() == V4 {
    let word = self.address_.d
    return "\{word & 255U}.\{(word >> 8) & 255U}.\{(word >> 16) & 255U}.\{word >> 24}.in-addr.arpa"
  }
  let digits = ip_padded(self.to_bigint().to_string(radix=16), 32)
  let out = StringBuilder()
  for index = 31; index >= 0; index = index - 1 {
    out.write_substring(digits, index, 1)
    out.write_string(".")
  }
  out.write_string("ip6.arpa")
  out.to_string()
}

///|
/// String formatting uses [[fill]align][0][width][.precision]s, with <, > or ^
/// alignment, one Unicode fill character and ASCII decimal width/precision
/// up to 2147483647. Width and precision count Unicode characters.
/// Numeric b/x/X/n formatting supports optional # prefix and _ grouping.
pub fn IpAddress::format(
  self : IpAddress,
  spec : String,
) -> String raise IpError {
  if spec == "" || spec == "s" {
    return self.to_string()
  }
  if spec.has_suffix("s") {
    return ip_format_string(self.to_string(), spec)
  }
  let mut rest = spec
  let mut alternate = false
  let mut grouped = false
  if rest.has_prefix("#") {
    alternate = true
    rest = rest[1:].to_owned()
  }
  if rest.has_prefix("_") {
    grouped = true
    rest = rest[1:].to_owned()
  }
  if rest != "b" && rest != "x" && rest != "X" && rest != "n" {
    raise InvalidAddress("unsupported address format: \{spec}")
  }
  let binary = rest == "b" || (rest == "n" && self.family() == V4)
  let radix = if binary { 2 } else { 16 }
  let width = self.max_prefixlen() / (if binary { 1 } else { 4 })
  let digits = ip_padded(self.to_bigint().to_string(radix~), width)
  let digits = if rest == "X" { digits.to_upper() } else { digits }
  let out = StringBuilder()
  if alternate {
    out.write_string(
      if binary {
        "0b"
      } else if rest == "X" {
        "0X"
      } else {
        "0x"
      },
    )
  }
  for i = 0; i < digits.length(); i = i + 1 {
    if grouped && i > 0 && i % 4 == 0 {
      out.write_string("_")
    }
    out.write_substring(digits, i, 1)
  }
  out.to_string()
}

///|
fn ip_format_alignment(character : Char) -> Bool {
  character == '<' || character == '>' || character == '^'
}

///|
/// The string subset used by address formatting; precision truncates text,
/// not address bits. Numeric formatting deliberately has its own grammar.
fn ip_format_string(text : String, spec : String) -> String raise IpError {
  let characters = spec.iter().to_array()
  let end = characters.length() - 1
  let mut index = 0
  let mut fill = ' '
  let mut alignment = '<'
  let mut explicit_fill = false
  if end >= 2 && ip_format_alignment(characters[1]) {
    fill = characters[0]
    alignment = characters[1]
    explicit_fill = true
    index = 2
  } else if end >= 1 && ip_format_alignment(characters[0]) {
    alignment = characters[0]
    index = 1
  }
  if index < end && characters[index] == '0' {
    if !explicit_fill {
      fill = '0'
    }
    index = index + 1
  }
  let mut width = 0
  while index < end && characters[index] != '.' {
    let digit = characters[index].to_int() - 48
    if digit < 0 || digit > 9 || width > (2147483647 - digit) / 10 {
      raise InvalidAddress("unsupported address format: \{spec}")
    }
    width = width * 10 + digit
    index = index + 1
  }
  let mut text = text
  if index < end {
    index = index + 1
    if index == end {
      raise InvalidAddress("unsupported address format: \{spec}")
    }
    let mut precision = 0
    while index < end {
      let digit = characters[index].to_int() - 48
      if digit < 0 || digit > 9 || precision > (2147483647 - digit) / 10 {
        raise InvalidAddress("unsupported address format: \{spec}")
      }
      precision = precision * 10 + digit
      index = index + 1
    }
    text = String::from_iter(text.iter().take(precision))
  }
  let padding = width - text.char_length()
  if padding <= 0 {
    return text
  }
  if alignment == '>' {
    String::make(padding, fill) + text
  } else if alignment == '^' {
    let left = padding / 2
    String::make(left, fill) + text + String::make(padding - left, fill)
  } else {
    text + String::make(padding, fill)
  }
}

///|
pub fn IpAddress::add(
  self : IpAddress,
  delta : @bigint.BigInt,
) -> IpAddress raise IpError {
  IpAddress::from_bigint(self.to_bigint() + delta, family=self.family())
}

///|
pub fn IpAddress::subtract(
  self : IpAddress,
  delta : @bigint.BigInt,
) -> IpAddress raise IpError {
  IpAddress::from_bigint(self.to_bigint() - delta, family=self.family())
}

///|
/// A total ordering: family, numeric value, then optional zone identifier.
pub impl Compare for IpAddress with fn compare(self, other) {
  let numeric = self.address_.compare(other.address_)
  if numeric != 0 {
    return numeric
  }
  match (self.scope_, other.scope_) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(a), Some(b)) => a.compare(b)
  }
}

///|
pub impl Hash for IpAddress with fn hash_combine(self, hasher) {
  hasher.combine(self.version())
  hasher.combine(self.address_.a)
  hasher.combine(self.address_.b)
  hasher.combine(self.address_.c)
  hasher.combine(self.address_.d)
  hasher.combine(self.scope_)
}

///|
pub impl Show for IpAddress with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub impl @debug.Debug for IpAddress with fn to_repr(self) {
  @debug.Repr(self.to_string())
}
