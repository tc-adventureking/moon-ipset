///|
/// Address families are distinct, including IPv4-mapped IPv6 addresses.
pub(all) enum Family {
  V4
  V6
} derive(Eq, Compare)

///|
pub extend Family with Eq::{equal, not_equal}

///|
pub extend Family with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Family with Show::{output, to_string}

///|
pub impl Show for Family with fn output(self, logger) {
  logger.write_string(if self == V4 { "IPv4" } else { "IPv6" })
}

///|
/// Invalid input is reported without constructing an invalid address or range.
pub(all) suberror IpError {
  InvalidAddress(String)
  InvalidPrefix(String)
  InvalidRange(String)
  HostBitsSet(String)
} derive(Eq)

///|
pub extend IpError with Eq::{equal, not_equal}

///|
pub extend IpError with Show::{output, to_string}

///|
pub impl Show for IpError with fn output(self, logger) {
  match self {
    InvalidAddress(text) => logger.write_string("Invalid IP address: \{text}")
    InvalidPrefix(text) => logger.write_string("Invalid CIDR prefix: \{text}")
    InvalidRange(text) => logger.write_string("Invalid address range: \{text}")
    HostBitsSet(text) =>
      logger.write_string("CIDR has nonzero host bits: \{text}")
  }
}

///|
/// An immutable address. The four words are in network (most significant first) order.
struct Address {
  family_ : Family
  a : UInt32
  b : UInt32
  c : UInt32
  d : UInt32
} derive(Eq)

///|
pub extend Address with Eq::{equal, not_equal}

///|
pub extend Address with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Address with Show::{output}

///|
pub impl Compare for Address with fn compare(self, other) {
  if self.family_ != other.family_ {
    if self.family_ == V4 {
      -1
    } else {
      1
    }
  } else if self.a != other.a {
    self.a.compare(other.a)
  } else if self.b != other.b {
    self.b.compare(other.b)
  } else if self.c != other.c {
    self.c.compare(other.c)
  } else {
    self.d.compare(other.d)
  }
}

///|
/// Returns the address family, without interpreting mapped addresses as IPv4.
pub fn Address::family(self : Address) -> Family {
  self.family_
}

///|
/// Returns the width of this address family in bits.
pub fn Address::width(self : Address) -> Int32 {
  if self.family_ == V4 {
    32
  } else {
    128
  }
}

///|
fn parse_v4_word(text : String) -> UInt32 raise IpError {
  let parts = text.split(".").to_array()
  if parts.length() != 4 {
    raise InvalidAddress(text)
  }
  let mut result = 0U
  for part in parts {
    if part.length() == 0 || part.length() > 3 {
      raise InvalidAddress(text)
    }
    if part.length() > 1 && part[0].to_int() == 48 {
      raise InvalidAddress(text)
    }
    let mut value = 0U
    for unit in part.code_units() {
      let digit = unit.to_int() - 48
      if digit < 0 || digit > 9 {
        raise InvalidAddress(text)
      }
      value = value * 10U + digit.reinterpret_as_uint()
    }
    if value > 255U {
      raise InvalidAddress(text)
    }
    result = (result << 8) | value
  }
  result
}

///|
fn parse_v6_groups(
  text : String,
  allow_v4 : Bool,
  original : String,
) -> Array[UInt32] raise IpError {
  let result : Array[UInt32] = []
  if text.is_empty() {
    return result
  }
  let groups = text.split(":").to_array()
  for index = 0; index < groups.length(); index = index + 1 {
    let group = groups[index].to_owned()
    if group.is_empty() {
      raise InvalidAddress(original)
    }
    if group.contains(".") {
      if !allow_v4 || index != groups.length() - 1 {
        raise InvalidAddress(original)
      }
      let word = parse_v4_word(group)
      result.push(word >> 16)
      result.push(word & 65535U)
    } else {
      if group.length() > 4 {
        raise InvalidAddress(original)
      }
      let mut word = 0U
      for unit in group.code_units() {
        let code = unit.to_int()
        let digit = if code >= 48 && code <= 57 {
          code - 48
        } else if code >= 65 && code <= 70 {
          code - 55
        } else if code >= 97 && code <= 102 {
          code - 87
        } else {
          raise InvalidAddress(original)
        }
        word = (word << 4) | digit.reinterpret_as_uint()
      }
      result.push(word)
    }
  }
  result
}

///|
/// Parses strict IPv4 or IPv6 text; rejects whitespace, zones, brackets, and ports.
pub fn Address::parse(text : String) -> Address raise IpError {
  if text.is_empty() || text.length() > 45 {
    raise InvalidAddress(text)
  }
  if !text.contains(":") {
    return { family_: V4, a: 0U, b: 0U, c: 0U, d: parse_v4_word(text), }
  }
  let groups : Array[UInt32] = match text.split_once("::") {
    None => {
      let full = parse_v6_groups(text, true, text)
      if full.length() != 8 {
        raise InvalidAddress(text)
      }
      full
    }
    Some((left, right)) => {
      if right.contains("::") {
        raise InvalidAddress(text)
      }
      let before = parse_v6_groups(left.to_owned(), false, text)
      let after = parse_v6_groups(right.to_owned(), true, text)
      let missing = 8 - before.length() - after.length()
      if missing < 1 {
        raise InvalidAddress(text)
      }
      for i = 0; i < missing; i = i + 1 {
        before.push(0U)
      }
      for word in after {
        before.push(word)
      }
      before
    }
  }
  {
    family_: V6,
    a: (groups[0] << 16) | groups[1],
    b: (groups[2] << 16) | groups[3],
    c: (groups[4] << 16) | groups[5],
    d: (groups[6] << 16) | groups[7],
  }
}

///|
/// Formats IPv4 dotted decimal or lowercase compressed IPv6 (including mapped addresses).
pub fn Address::to_string(self : Address) -> String {
  if self.family_ == V4 {
    return "\{self.d >> 24}.\{(self.d >> 16) & 255U}.\{(self.d >> 8) & 255U}.\{self.d & 255U}"
  }
  let groups = [
    self.a >> 16,
    self.a & 65535U,
    self.b >> 16,
    self.b & 65535U,
    self.c >> 16,
    self.c & 65535U,
    self.d >> 16,
    self.d & 65535U,
  ]
  let mut best_start = -1
  let mut best_length = 1
  let mut index = 0
  while index < 8 {
    if groups[index] == 0U {
      let start = index
      while index < 8 && groups[index] == 0U {
        index = index + 1
      }
      let length = index - start
      if length > best_length {
        best_start = start
        best_length = length
      }
    } else {
      index = index + 1
    }
  }
  let out = StringBuilder()
  index = 0
  while index < 8 {
    if index == best_start {
      out.write_string("::")
      index = index + best_length
    } else {
      if index > 0 && index != best_start + best_length {
        out.write_string(":")
      }
      out.write_string(groups[index].to_string(radix=16))
      index = index + 1
    }
  }
  out.to_string()
}

///|
pub impl Show for Address with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Returns the next address in the same family, or None at its maximum value.
pub fn Address::next(self : Address) -> Address? {
  if self.d != 4294967295U {
    Some({ ..self, d: self.d + 1U, })
  } else if self.family_ == V4 {
    None
  } else if self.c != 4294967295U {
    Some({ ..self, c: self.c + 1U, d: 0U, })
  } else if self.b != 4294967295U {
    Some({ ..self, b: self.b + 1U, c: 0U, d: 0U, })
  } else if self.a != 4294967295U {
    Some({ ..self, a: self.a + 1U, b: 0U, c: 0U, d: 0U, })
  } else {
    None
  }
}

///|
/// Returns the preceding address in the same family, or None at zero.
pub fn Address::previous(self : Address) -> Address? {
  if self.d != 0U {
    Some({ ..self, d: self.d - 1U, })
  } else if self.family_ == V4 {
    None
  } else if self.c != 0U {
    Some({ ..self, c: self.c - 1U, d: 4294967295U, })
  } else if self.b != 0U {
    Some({ ..self, b: self.b - 1U, c: 4294967295U, d: 4294967295U, })
  } else if self.a != 0U {
    Some({
      ..self,
      a: self.a - 1U,
      b: 4294967295U,
      c: 4294967295U,
      d: 4294967295U,
    })
  } else {
    None
  }
}

///|
fn word_mask(bits : Int32) -> UInt32 {
  if bits <= 0 {
    0U
  } else if bits >= 32 {
    4294967295U
  } else {
    4294967295U << (32 - bits)
  }
}

///|
fn Address::mask(self : Address, prefix : Int32) -> Address {
  let bits = if self.family_ == V4 { prefix + 96 } else { prefix }
  {
    ..self,
    a: self.a & word_mask(bits),
    b: self.b & word_mask(bits - 32),
    c: self.c & word_mask(bits - 64),
    d: self.d & word_mask(bits - 96),
  }
}

///|
fn Address::block_end(self : Address, prefix : Int32) -> Address {
  let bits = if self.family_ == V4 { prefix + 96 } else { prefix }
  {
    ..self,
    a: self.a | word_mask(bits).lnot(),
    b: self.b | word_mask(bits - 32).lnot(),
    c: self.c | word_mask(bits - 64).lnot(),
    d: self.d | word_mask(bits - 96).lnot(),
  }
}

///|
fn Address::trailing_zeros(self : Address) -> Int32 {
  if self.d != 0U || self.family_ == V4 {
    self.d.ctz()
  } else if self.c != 0U {
    32 + self.c.ctz()
  } else if self.b != 0U {
    64 + self.b.ctz()
  } else {
    96 + self.a.ctz()
  }
}
