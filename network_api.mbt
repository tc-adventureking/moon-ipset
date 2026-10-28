///|
/// A dual-stack IP network. Scoped IPv6 network addresses retain their scope
/// only when construction does not need to clear host bits, matching Python.
struct IpNetwork {
  cidr_ : Cidr
  scope_ : String?
} derive(Eq)

///|
pub extend IpNetwork with Eq::{equal, not_equal}

///|
pub extend IpNetwork with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend IpNetwork with Show::{output}

///|
pub extend IpNetwork with Hash::{hash, hash_combine}

///|
pub impl Show for IpNetwork with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub impl Hash for IpNetwork with fn hash_combine(self, hasher) {
  hasher.combine(self.network_address())
  hasher.combine(self.prefixlen())
}

///|
/// Total order: family (IPv4 first), numeric address, scope, then prefix length.
/// A missing scope precedes a present scope; present scopes compare as strings.
/// Unlike compare_networks or get_mixed_type_key, this order includes scope.
pub impl Compare for IpNetwork with fn compare(self, other) {
  let address_order = self.network_address().compare(other.network_address())
  if address_order != 0 {
    address_order
  } else {
    self.prefixlen().compare(other.prefixlen())
  }
}

///|
/// Split the address and mask, accepting an omitted host-width prefix.
fn ip_split_prefix(text : String) -> (IpAddress, Int32) raise IpError {
  let (address_text, mask_text) = match text.split_once("/") {
    Some((address, mask)) => (address.to_owned(), Some(mask.to_owned()))
    None => (text, None)
  }
  let address = IpAddress::parse(address_text)
  let prefix = match mask_text {
    None => address.max_prefixlen()
    Some(mask) => ip_parse_prefix(mask, address.family())
  }
  (address, prefix)
}

///|
/// An all-zero dotted mask is /0, and all ones is /32; otherwise accept
/// contiguous netmask bits or their contiguous hostmask complement.
fn ip_parse_prefix(text : String, family : Family) -> Int32 raise IpError {
  let width = if family == V4 { 32 } else { 128 }
  if text.contains(".") && family == V4 {
    let mask = Address::parse(text) catch { _ => raise InvalidPrefix(text) }
    if mask.family() != V4 {
      raise InvalidPrefix(text)
    }
    for prefix = 0; prefix <= 32; prefix = prefix + 1 {
      if mask.d == word_mask(prefix) {
        return prefix
      }
    }
    for prefix = 0; prefix <= 32; prefix = prefix + 1 {
      if mask.d == word_mask(prefix).lnot() {
        return prefix
      }
    }
    raise InvalidPrefix(text)
  }
  if text.is_empty() {
    raise InvalidPrefix(text)
  }
  let mut prefix = 0
  for unit in text.code_units() {
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 {
      raise InvalidPrefix(text)
    }
    // Checking before multiplication also handles arbitrarily long inputs.
    if prefix > width / 10 || (prefix == width / 10 && digit > width % 10) {
      raise InvalidPrefix(text)
    }
    prefix = prefix * 10 + digit
  }
  prefix
}

///|
/// Parse an IPv4/IPv6 network; unlike legacy Cidr::parse, strict defaults true.
pub fn IpNetwork::parse(
  text : String,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  let (address, prefix) = ip_split_prefix(text)
  IpNetwork::from_address(address, prefix, strict~)
}

///|
pub fn ip_network(
  text : String,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  IpNetwork::parse(text, strict~)
}

///|
pub fn ipv4_network(
  text : String,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  let network = IpNetwork::parse(text, strict~)
  if network.family() != V4 {
    raise InvalidAddress(text)
  }
  network
}

///|
pub fn ipv6_network(
  text : String,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  let network = IpNetwork::parse(text, strict~)
  if network.family() != V6 {
    raise InvalidAddress(text)
  }
  network
}

///|
pub fn IpNetwork::from_address(
  address : IpAddress,
  prefix : Int32,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  let raw = address.as_address()
  let cidr = Cidr::new(raw, prefix, strict~)
  let scope = if cidr.network() == raw { address.scope_id() } else { None }
  { cidr_: cidr, scope_: scope, }
}

///|
/// Construct from a typed address and decimal prefix, IPv4 netmask or hostmask.
/// IPv6 accepts a decimal prefix only. Strict defaults true, as with parse.
pub fn IpNetwork::from_address_mask(
  address : IpAddress,
  mask : String,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  let prefix = ip_parse_prefix(mask, address.family())
  IpNetwork::from_address(address, prefix, strict~)
}

///|
pub fn IpNetwork::from_cidr(cidr : Cidr) -> IpNetwork {
  { cidr_: cidr, scope_: None, }
}

///|
pub fn IpNetwork::as_cidr(self : IpNetwork) -> Cidr {
  self.cidr_
}

///|
pub fn IpNetwork::from_bigint(
  value : @bigint.BigInt,
  prefix? : Int32,
  family? : Family,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  let address = IpAddress::from_bigint(value, family?)
  IpNetwork::from_address(
    address,
    prefix.unwrap_or(address.max_prefixlen()),
    strict~,
  )
}

///|
pub fn IpNetwork::from_bytes(
  bytes : Bytes,
  prefix? : Int32,
  strict~ : Bool = true,
) -> IpNetwork raise IpError {
  let address = IpAddress::from_bytes(bytes)
  IpNetwork::from_address(
    address,
    prefix.unwrap_or(address.max_prefixlen()),
    strict~,
  )
}

///|
pub fn IpNetwork::family(self : IpNetwork) -> Family {
  self.cidr_.network().family()
}

///|
pub fn IpNetwork::version(self : IpNetwork) -> Int32 {
  if self.family() == V4 {
    4
  } else {
    6
  }
}

///|
pub fn IpNetwork::max_prefixlen(self : IpNetwork) -> Int32 {
  self.cidr_.network().width()
}

///|
pub fn IpNetwork::prefixlen(self : IpNetwork) -> Int32 {
  self.cidr_.prefix()
}

///|
pub fn IpNetwork::network_address(self : IpNetwork) -> IpAddress {
  { address_: self.cidr_.network(), scope_: self.scope_, }
}

///|
/// Inclusive final address; IPv6 uses this name for parity with ipaddress.
pub fn IpNetwork::broadcast_address(self : IpNetwork) -> IpAddress {
  IpAddress::from_address(self.cidr_.last())
}

///|
pub fn IpNetwork::netmask(self : IpNetwork) -> IpAddress {
  let prefix = self.prefixlen()
  let raw = if self.family() == V4 {
    { family_: V4, a: 0U, b: 0U, c: 0U, d: word_mask(prefix), }
  } else {
    {
      family_: V6,
      a: word_mask(prefix),
      b: word_mask(prefix - 32),
      c: word_mask(prefix - 64),
      d: word_mask(prefix - 96),
    }
  }
  IpAddress::from_address(raw)
}

///|
pub fn IpNetwork::hostmask(self : IpNetwork) -> IpAddress {
  let raw = self.netmask().as_address()
  IpAddress::from_address(
    if self.family() == V4 {
      { ..raw, d: raw.d.lnot(), }
    } else {
      {
        ..raw,
        a: raw.a.lnot(),
        b: raw.b.lnot(),
        c: raw.c.lnot(),
        d: raw.d.lnot(),
      }
    },
  )
}

///|
/// Exact cardinality, including the 2^128 addresses of IPv6 /0.
pub fn IpNetwork::num_addresses(self : IpNetwork) -> @bigint.BigInt {
  1N << (self.max_prefixlen() - self.prefixlen())
}

///|
pub fn IpNetwork::to_string(self : IpNetwork) -> String {
  "\{self.network_address()}/\{self.prefixlen()}"
}

///|
pub fn IpNetwork::compressed(self : IpNetwork) -> String {
  self.to_string()
}

///|
pub fn IpNetwork::with_prefixlen(self : IpNetwork) -> String {
  self.to_string()
}

///|
pub fn IpNetwork::with_netmask(self : IpNetwork) -> String {
  "\{self.network_address()}/\{self.netmask()}"
}

///|
pub fn IpNetwork::with_hostmask(self : IpNetwork) -> String {
  "\{self.network_address()}/\{self.hostmask()}"
}

///|
/// Expanded IPv6 representation. Scope is retained (Python's scoped exploded
/// formatter raises instead); this method remains total for valid values.
pub fn IpNetwork::exploded(self : IpNetwork) -> String {
  let raw = self.cidr_.network()
  let numeric = if self.family() == V4 {
    raw.to_string()
  } else {
    [
      raw.a >> 16,
      raw.a & 65535U,
      raw.b >> 16,
      raw.b & 65535U,
      raw.c >> 16,
      raw.c & 65535U,
      raw.d >> 16,
      raw.d & 65535U,
    ]
    .map(g => ip_padded(g.to_string(radix=16), 4))
    .join(":")
  }
  let scoped = match self.scope_ {
    None => numeric
    Some(scope) => "\{numeric}%\{scope}"
  }
  "\{scoped}/\{self.prefixlen()}"
}

///|
pub fn IpNetwork::contains(self : IpNetwork, address : IpAddress) -> Bool {
  address.family() == self.family() &&
  address.as_address().mask(self.prefixlen()) == self.cidr_.network()
}

///|
pub fn IpNetwork::overlaps(self : IpNetwork, other : IpNetwork) -> Bool {
  self.family() == other.family() &&
  self.cidr_.network() <= other.cidr_.last() &&
  other.cidr_.network() <= self.cidr_.last()
}

///|
/// Compare numeric network addresses, then prefixes; return -1, 0 or 1.
/// Different families raise InvalidRange. Scope is intentionally ignored:
/// unlike Compare, distinct scoped objects can compare equal here. This avoids
/// Python 3.13.2 returning 1 in both directions for equal bases with new scopes.
pub fn IpNetwork::compare_networks(
  self : IpNetwork,
  other : IpNetwork,
) -> Int32 raise IpError {
  if self.family() != other.family() {
    raise InvalidRange("network families differ")
  }
  let address_order = self.cidr_.network().compare(other.cidr_.network())
  if address_order < 0 {
    -1
  } else if address_order > 0 {
    1
  } else if self.prefixlen() < other.prefixlen() {
    -1
  } else if self.prefixlen() > other.prefixlen() {
    1
  } else {
    0
  }
}

///|
/// Numeric containment ignores IPv6 scope, including equal network bases.
/// This differs from Python's scope-sensitive endpoint equality checks.
pub fn IpNetwork::subnet_of(
  self : IpNetwork,
  other : IpNetwork,
) -> Bool raise IpError {
  if self.family() != other.family() {
    raise InvalidRange("network families differ")
  }
  self.cidr_.network() >= other.cidr_.network() &&
  self.cidr_.last() <= other.cidr_.last()
}

///|
pub fn IpNetwork::supernet_of(
  self : IpNetwork,
  other : IpNetwork,
) -> Bool raise IpError {
  other.subnet_of(self)
}

///|
fn ip_address_iter(first : Address, last : Address) -> Iter[IpAddress] {
  let mut cursor = if first <= last { Some(first) } else { None }
  Iter::new(fn() {
    match cursor {
      None => None
      Some(address) => {
        cursor = if address == last { None } else { address.next() }
        Some(IpAddress::from_address(address))
      }
    }
  })
}

///|
/// Lazily iterate all numeric addresses, without allocating the address space.
pub fn IpNetwork::iter(self : IpNetwork) -> Iter[IpAddress] {
  ip_address_iter(self.cidr_.network(), self.cidr_.last())
}

///|
/// IPv4 excludes network/broadcast except /31 and /32; IPv6 excludes subnet
/// router anycast except /127 and /128. Iteration uses constant auxiliary space.
pub fn IpNetwork::hosts(self : IpNetwork) -> Iter[IpAddress] {
  if self.prefixlen() == self.max_prefixlen() {
    return Iter::singleton(self.network_address())
  }
  if self.prefixlen() == self.max_prefixlen() - 1 {
    return self.iter()
  }
  let first = self.cidr_.network().next().unwrap()
  let last = if self.family() == V4 {
    self.cidr_.last().previous().unwrap()
  } else {
    self.cidr_.last()
  }
  ip_address_iter(first, last)
}

///|
/// Zero-based address indexing; negative indices count back from the end.
pub fn IpNetwork::nth(
  self : IpNetwork,
  index : @bigint.BigInt,
) -> IpAddress raise IpError {
  let offset = if index < 0N { self.num_addresses() + index } else { index }
  if offset < 0N || offset >= self.num_addresses() {
    raise InvalidRange("address index out of bounds")
  }
  IpAddress::from_bigint(
    self.network_address().to_bigint() + offset,
    family=self.family(),
  )
}

///|
/// Lazily split into equal-size subnets. Only one resulting block is retained.
pub fn IpNetwork::subnets(
  self : IpNetwork,
  prefixlen_diff~ : Int32 = 1,
  new_prefix? : Int32,
) -> Iter[IpNetwork] raise IpError {
  if self.prefixlen() == self.max_prefixlen() {
    return Iter::singleton(self)
  }
  let prefix = match new_prefix {
    Some(prefix) => {
      if prefixlen_diff != 1 ||
        prefix < self.prefixlen() ||
        prefix > self.max_prefixlen() {
        raise InvalidPrefix("invalid subnet prefix or conflicting options")
      }
      prefix
    }
    None => {
      if prefixlen_diff < 0 ||
        prefixlen_diff > self.max_prefixlen() - self.prefixlen() {
        raise InvalidPrefix("invalid subnet prefix length difference")
      }
      self.prefixlen() + prefixlen_diff
    }
  }
  let end = self.cidr_.last()
  let mut cursor = Some(self.cidr_.network())
  Iter::new(fn() {
    match cursor {
      None => None
      Some(address) => {
        let cidr = cidr_from_normalized(address, prefix)
        cursor = if cidr.last() == end { None } else { cidr.last().next() }
        Some(IpNetwork::from_cidr(cidr))
      }
    }
  })
}

///|
pub fn IpNetwork::supernet(
  self : IpNetwork,
  prefixlen_diff~ : Int32 = 1,
  new_prefix? : Int32,
) -> IpNetwork raise IpError {
  if self.prefixlen() == 0 {
    return self
  }
  let prefix = match new_prefix {
    Some(prefix) => {
      if prefixlen_diff != 1 || prefix < 0 || prefix > self.prefixlen() {
        raise InvalidPrefix("invalid supernet prefix or conflicting options")
      }
      prefix
    }
    None => {
      if prefixlen_diff < 0 || prefixlen_diff > self.prefixlen() {
        raise InvalidPrefix("invalid supernet prefix length difference")
      }
      self.prefixlen() - prefixlen_diff
    }
  }
  IpNetwork::from_cidr(
    cidr_from_normalized(self.cidr_.network().mask(prefix), prefix),
  )
}

///|
/// Remove a contained network in at most 128 lazy binary partition steps.
/// Results use Python's sibling-first order rather than numeric sorting.
/// Containment uses numeric ranges and output networks do not retain scope.
pub fn IpNetwork::address_exclude(
  self : IpNetwork,
  other : IpNetwork,
) -> Iter[IpNetwork] raise IpError {
  if !other.subnet_of(self) {
    raise InvalidRange("excluded network is not contained")
  }
  let mut current = self.cidr_
  let target = other.cidr_
  Iter::new(fn() {
    if current.prefix() >= target.prefix() {
      return None
    }
    let prefix = current.prefix() + 1
    let left = cidr_from_normalized(current.network(), prefix)
    let right = cidr_from_normalized(left.last().next().unwrap(), prefix)
    if target.network() <= left.last() {
      current = left
      Some(IpNetwork::from_cidr(right))
    } else {
      current = right
      Some(IpNetwork::from_cidr(left))
    }
  })
}

///|
pub fn IpNetwork::is_private(self : IpNetwork) -> Bool {
  let first = self.cidr_.network()
  let last = self.cidr_.last()
  ip_private_networks(self.family())
  .iter()
  .any(fn(range) { ip_in_cidr(first, range) && ip_in_cidr(last, range) }) &&
  ip_private_exceptions(self.family())
  .iter()
  .all(fn(range) { !ip_in_cidr(first, range) && !ip_in_cidr(last, range) })
}

///|
pub fn IpNetwork::is_global(self : IpNetwork) -> Bool {
  let cgnat = self.family() == V4 &&
    self.cidr_.network().d >= 0x64400000U &&
    self.cidr_.last().d <= 0x647fffffU
  !cgnat && !self.is_private()
}

///|
pub fn IpNetwork::is_multicast(self : IpNetwork) -> Bool {
  self.network_address().is_multicast() &&
  self.broadcast_address().is_multicast()
}

///|
pub fn IpNetwork::is_reserved(self : IpNetwork) -> Bool {
  self.network_address().is_reserved() && self.broadcast_address().is_reserved()
}

///|
pub fn IpNetwork::is_unspecified(self : IpNetwork) -> Bool {
  self.network_address().is_unspecified() &&
  self.broadcast_address().is_unspecified()
}

///|
pub fn IpNetwork::is_loopback(self : IpNetwork) -> Bool {
  self.network_address().is_loopback() && self.broadcast_address().is_loopback()
}

///|
pub fn IpNetwork::is_link_local(self : IpNetwork) -> Bool {
  self.network_address().is_link_local() &&
  self.broadcast_address().is_link_local()
}

///|
pub fn IpNetwork::is_site_local(self : IpNetwork) -> Bool {
  self.network_address().is_site_local() &&
  self.broadcast_address().is_site_local()
}

///|
/// Exact minimal CIDR cover of an inclusive numeric range, in ascending order.
/// Ignore IPv6 scope on both endpoints and omit it from the resulting cover.
pub fn summarize_address_range(
  first : IpAddress,
  last : IpAddress,
) -> Array[IpNetwork] raise IpError {
  let interval = Interval::new(first.as_address(), last.as_address())
  IpSet::from_ranges([interval]).cidrs().map(IpNetwork::from_cidr)
}

///|
/// Merge overlapping/adjacent networks of one address family. Scopes are not
/// address bits and are omitted from the resulting canonical numeric cover.
pub fn collapse_addresses(
  networks : Array[IpNetwork],
) -> Array[IpNetwork] raise IpError {
  let ranges : Array[Interval] = []
  let mut family : Family? = None
  for network in networks {
    match family {
      Some(previous) if previous != network.family() =>
        raise InvalidRange("cannot collapse mixed address families")
      _ => family = Some(network.family())
    }
    ranges.push(Interval::new(network.cidr_.network(), network.cidr_.last()))
  }
  IpSet::from_ranges(ranges).cidrs().map(IpNetwork::from_cidr)
}

///|
pub extend IpNetwork with @debug.Debug::{to_repr}

///|
pub impl @debug.Debug for IpNetwork with fn to_repr(self) {
  @debug.Repr(self.to_string())
}
