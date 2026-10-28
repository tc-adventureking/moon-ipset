///|
// Special-address registry prefixes matching the selected CPython ipaddress
// reference. Data only; lookup and address operations are independently implemented.

///|
fn ip_private_networks(family : Family) -> Array[Cidr] {
  if family == V4 {
    ip_private_v4
  } else {
    ip_private_v6
  }
}

///|
fn ip_private_exceptions(family : Family) -> Array[Cidr] {
  if family == V4 {
    ip_exceptions_v4
  } else {
    ip_exceptions_v6
  }
}

///|
fn ip_in_cidr(address : Address, network : Cidr) -> Bool {
  address.family() == network.network().family() &&
  address >= network.network() &&
  address <= network.last()
}

///|
pub fn IpAddress::ipv4_mapped(self : IpAddress) -> IpAddress? {
  let a = self.address_
  if a.family_ == V6 && a.a == 0U && a.b == 0U && a.c == 65535U {
    Some(IpAddress::from_address({ family_: V4, a: 0U, b: 0U, c: 0U, d: a.d, }))
  } else {
    None
  }
}

///|
pub fn IpAddress::ipv6_mapped(self : IpAddress) -> IpAddress? {
  if self.family() == V4 {
    Some(
      IpAddress::from_address({
        family_: V6,
        a: 0U,
        b: 0U,
        c: 65535U,
        d: self.address_.d,
      }),
    )
  } else {
    None
  }
}

///|
pub fn IpAddress::sixtofour(self : IpAddress) -> IpAddress? {
  let a = self.address_
  if a.family_ == V6 && a.a >> 16 == 8194U {
    Some(
      IpAddress::from_address({
        family_: V4,
        a: 0U,
        b: 0U,
        c: 0U,
        d: (a.a << 16) | (a.b >> 16),
      }),
    )
  } else {
    None
  }
}

///|
pub fn IpAddress::teredo(self : IpAddress) -> (IpAddress, IpAddress)? {
  let a = self.address_
  if a.family_ == V6 && a.a == 536936448U {
    Some(
      (
        IpAddress::from_address({ family_: V4, a: 0U, b: 0U, c: 0U, d: a.b, }),
        IpAddress::from_address({
          family_: V4,
          a: 0U,
          b: 0U,
          c: 0U,
          d: a.d.lnot(),
        }),
      ),
    )
  } else {
    None
  }
}

///|
pub fn IpAddress::is_private(self : IpAddress) -> Bool {
  match self.ipv4_mapped() {
    Some(mapped) => return mapped.is_private()
    None => ()
  }
  ip_private_networks(self.family()).any(fn(n) { ip_in_cidr(self.address_, n) }) &&
  !ip_private_exceptions(self.family()).any(fn(n) {
    ip_in_cidr(self.address_, n)
  })
}

///|
pub fn IpAddress::is_global(self : IpAddress) -> Bool {
  match self.ipv4_mapped() {
    Some(mapped) => return mapped.is_global()
    None => ()
  }
  if self.family() == V4 && (self.address_.d & 4290772992U) == 1681915904U {
    // Shared CGNAT 100.64.0.0/10 is neither private nor global.
    false
  } else {
    !self.is_private()
  }
}

///|
pub fn IpAddress::is_reserved(self : IpAddress) -> Bool {
  match self.ipv4_mapped() {
    Some(mapped) => return mapped.is_reserved()
    None => ()
  }
  if self.family() == V4 {
    self.address_.d >> 28 == 15U
  } else {
    ip_reserved_v6.any(fn(n) { ip_in_cidr(self.address_, n) })
  }
}

///|
pub fn IpAddress::is_multicast(self : IpAddress) -> Bool {
  match self.ipv4_mapped() {
    Some(mapped) => return mapped.is_multicast()
    None => ()
  }
  if self.family() == V4 {
    self.address_.d >> 28 == 14U
  } else {
    self.address_.a >> 24 == 255U
  }
}

///|
pub fn IpAddress::is_unspecified(self : IpAddress) -> Bool {
  match self.ipv4_mapped() {
    Some(mapped) => return mapped.is_unspecified()
    None => ()
  }
  self.address_.a == 0U &&
  self.address_.b == 0U &&
  self.address_.c == 0U &&
  self.address_.d == 0U
}

///|
pub fn IpAddress::is_loopback(self : IpAddress) -> Bool {
  match self.ipv4_mapped() {
    Some(mapped) => return mapped.is_loopback()
    None => ()
  }
  if self.family() == V4 {
    self.address_.d >> 24 == 127U
  } else {
    self.address_.a == 0U &&
    self.address_.b == 0U &&
    self.address_.c == 0U &&
    self.address_.d == 1U
  }
}

///|
pub fn IpAddress::is_link_local(self : IpAddress) -> Bool {
  match self.ipv4_mapped() {
    Some(mapped) => return mapped.is_link_local()
    None => ()
  }
  if self.family() == V4 {
    self.address_.d >> 16 == 43518U
  } else {
    self.address_.a >> 22 == 1018U
  }
}

///|
pub fn IpAddress::is_site_local(self : IpAddress) -> Bool {
  self.family() == V6 && self.address_.a >> 22 == 1019U
}

///|
let ip_private_v4 : Array[Cidr] = [
  cidr_from_normalized({ family_: V4, a: 0U, b: 0U, c: 0U, d: 0U, }, 8),
  cidr_from_normalized({ family_: V4, a: 0U, b: 0U, c: 0U, d: 167772160U, }, 8),
  cidr_from_normalized({ family_: V4, a: 0U, b: 0U, c: 0U, d: 2130706432U, }, 8),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 2851995648U, },
    16,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 2886729728U, },
    12,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3221225472U, },
    24,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3221225642U, },
    31,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3221225984U, },
    24,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3232235520U, },
    16,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3323068416U, },
    15,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3325256704U, },
    24,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3405803776U, },
    24,
  ),
  cidr_from_normalized({ family_: V4, a: 0U, b: 0U, c: 0U, d: 4026531840U, }, 4),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 4294967295U, },
    32,
  ),
]

///|
let ip_exceptions_v4 : Array[Cidr] = [
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3221225481U, },
    32,
  ),
  cidr_from_normalized(
    { family_: V4, a: 0U, b: 0U, c: 0U, d: 3221225482U, },
    32,
  ),
]

///|
let ip_private_v6 : Array[Cidr] = [
  cidr_from_normalized({ family_: V6, a: 0U, b: 0U, c: 0U, d: 1U, }, 128),
  cidr_from_normalized({ family_: V6, a: 0U, b: 0U, c: 0U, d: 0U, }, 128),
  cidr_from_normalized({ family_: V6, a: 0U, b: 0U, c: 65535U, d: 0U, }, 96),
  cidr_from_normalized(
    { family_: V6, a: 6619035U, b: 65536U, c: 0U, d: 0U, },
    48,
  ),
  cidr_from_normalized({ family_: V6, a: 16777216U, b: 0U, c: 0U, d: 0U, }, 64),
  cidr_from_normalized({ family_: V6, a: 536936448U, b: 0U, c: 0U, d: 0U, }, 23),
  cidr_from_normalized({ family_: V6, a: 536939960U, b: 0U, c: 0U, d: 0U, }, 32),
  cidr_from_normalized({ family_: V6, a: 537001984U, b: 0U, c: 0U, d: 0U, }, 16),
  cidr_from_normalized(
    { family_: V6, a: 1073676288U, b: 0U, c: 0U, d: 0U, },
    20,
  ),
  cidr_from_normalized({ family_: V6, a: 4227858432U, b: 0U, c: 0U, d: 0U, }, 7),
  cidr_from_normalized(
    { family_: V6, a: 4269801472U, b: 0U, c: 0U, d: 0U, },
    10,
  ),
]

///|
let ip_exceptions_v6 : Array[Cidr] = [
  cidr_from_normalized(
    { family_: V6, a: 536936449U, b: 0U, c: 0U, d: 1U, },
    128,
  ),
  cidr_from_normalized(
    { family_: V6, a: 536936449U, b: 0U, c: 0U, d: 2U, },
    128,
  ),
  cidr_from_normalized({ family_: V6, a: 536936451U, b: 0U, c: 0U, d: 0U, }, 32),
  cidr_from_normalized(
    { family_: V6, a: 536936452U, b: 17956864U, c: 0U, d: 0U, },
    48,
  ),
  cidr_from_normalized({ family_: V6, a: 536936480U, b: 0U, c: 0U, d: 0U, }, 28),
  cidr_from_normalized({ family_: V6, a: 536936496U, b: 0U, c: 0U, d: 0U, }, 28),
]

///|
let ip_reserved_v6 : Array[Cidr] = [
  cidr_from_normalized({ family_: V6, a: 0U, b: 0U, c: 0U, d: 0U, }, 8),
  cidr_from_normalized({ family_: V6, a: 16777216U, b: 0U, c: 0U, d: 0U, }, 8),
  cidr_from_normalized({ family_: V6, a: 33554432U, b: 0U, c: 0U, d: 0U, }, 7),
  cidr_from_normalized({ family_: V6, a: 67108864U, b: 0U, c: 0U, d: 0U, }, 6),
  cidr_from_normalized({ family_: V6, a: 134217728U, b: 0U, c: 0U, d: 0U, }, 5),
  cidr_from_normalized({ family_: V6, a: 268435456U, b: 0U, c: 0U, d: 0U, }, 4),
  cidr_from_normalized({ family_: V6, a: 1073741824U, b: 0U, c: 0U, d: 0U, }, 3),
  cidr_from_normalized({ family_: V6, a: 1610612736U, b: 0U, c: 0U, d: 0U, }, 3),
  cidr_from_normalized({ family_: V6, a: 2147483648U, b: 0U, c: 0U, d: 0U, }, 3),
  cidr_from_normalized({ family_: V6, a: 2684354560U, b: 0U, c: 0U, d: 0U, }, 3),
  cidr_from_normalized({ family_: V6, a: 3221225472U, b: 0U, c: 0U, d: 0U, }, 3),
  cidr_from_normalized({ family_: V6, a: 3758096384U, b: 0U, c: 0U, d: 0U, }, 4),
  cidr_from_normalized({ family_: V6, a: 4026531840U, b: 0U, c: 0U, d: 0U, }, 5),
  cidr_from_normalized({ family_: V6, a: 4160749568U, b: 0U, c: 0U, d: 0U, }, 6),
  cidr_from_normalized({ family_: V6, a: 4261412864U, b: 0U, c: 0U, d: 0U, }, 9),
]
