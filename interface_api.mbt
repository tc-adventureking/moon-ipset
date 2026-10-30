///|
/// An IP host address paired with a network prefix. Unlike IpNetwork, this
/// type preserves host bits. It models a value, not an OS network adapter.
struct IpInterface {
  address_ : IpAddress
  network_ : IpNetwork
} derive(Eq)

///|
pub extend IpInterface with Eq::{equal, not_equal}

///|
pub extend IpInterface with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend IpInterface with Show::{output}

///|
pub extend IpInterface with Hash::{hash, hash_combine}

///|
pub impl Show for IpInterface with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub impl Hash for IpInterface with fn hash_combine(self, hasher) {
  hasher.combine(self.address_)
  hasher.combine(self.network_)
}

///|
pub impl Compare for IpInterface with fn compare(self, other) {
  let order = self.network_.compare(other.network_)
  if order != 0 {
    order
  } else {
    self.address_.compare(other.address_)
  }
}

///|
pub fn IpInterface::parse(text : String) -> IpInterface raise IpError {
  let (address, prefix) = ip_split_prefix(text)
  IpInterface::from_address(address, prefix)
}

///|
pub fn ip_interface(text : String) -> IpInterface raise IpError {
  IpInterface::parse(text)
}

///|
pub fn ipv4_interface(text : String) -> IpInterface raise IpError {
  let interface = IpInterface::parse(text)
  if interface.family() != V4 {
    raise InvalidAddress(text)
  }
  interface
}

///|
pub fn ipv6_interface(text : String) -> IpInterface raise IpError {
  let interface = IpInterface::parse(text)
  if interface.family() != V6 {
    raise InvalidAddress(text)
  }
  interface
}

///|
pub fn IpInterface::from_address(
  address : IpAddress,
  prefix : Int32,
) -> IpInterface raise IpError {
  {
    address_: address,
    network_: IpNetwork::from_address(address, prefix, strict=false),
  }
}

///|
/// Pair a typed host address with a decimal prefix, IPv4 netmask or hostmask.
/// Preserve host bits and scope. IPv6 accepts a decimal prefix only.
pub fn IpInterface::from_address_mask(
  address : IpAddress,
  mask : String,
) -> IpInterface raise IpError {
  IpInterface::from_address(address, ip_parse_prefix(mask, address.family()))
}

///|
pub fn IpInterface::from_bigint(
  value : @bigint.BigInt,
  prefix? : Int32,
  family? : Family,
) -> IpInterface raise IpError {
  let address = IpAddress::from_bigint(value, family?)
  IpInterface::from_address(address, prefix.unwrap_or(address.max_prefixlen()))
}

///|
pub fn IpInterface::from_bytes(
  bytes : Bytes,
  prefix? : Int32,
) -> IpInterface raise IpError {
  let address = IpAddress::from_bytes(bytes)
  IpInterface::from_address(address, prefix.unwrap_or(address.max_prefixlen()))
}

///|
/// Numeric host address with no scope identifier, like Python's .ip property.
pub fn IpInterface::ip(self : IpInterface) -> IpAddress {
  self.address_.unscoped()
}

///|
/// The original host address including an optional IPv6 scope identifier.
pub fn IpInterface::address(self : IpInterface) -> IpAddress {
  self.address_
}

///|
pub fn IpInterface::network(self : IpInterface) -> IpNetwork {
  self.network_
}

///|
pub fn IpInterface::prefixlen(self : IpInterface) -> Int32 {
  self.network_.prefixlen()
}

///|
pub fn IpInterface::family(self : IpInterface) -> Family {
  self.address_.family()
}

///|
pub fn IpInterface::version(self : IpInterface) -> Int32 {
  self.address_.version()
}

///|
pub fn IpInterface::max_prefixlen(self : IpInterface) -> Int32 {
  self.address_.max_prefixlen()
}

///|
pub fn IpInterface::scope_id(self : IpInterface) -> String? {
  self.address_.scope_id()
}

///|
pub fn IpInterface::netmask(self : IpInterface) -> IpAddress {
  self.network_.netmask()
}

///|
pub fn IpInterface::hostmask(self : IpInterface) -> IpAddress {
  self.network_.hostmask()
}

///|
pub fn IpInterface::to_string(self : IpInterface) -> String {
  "\{self.address_}/\{self.prefixlen()}"
}

///|
pub fn IpInterface::compressed(self : IpInterface) -> String {
  self.to_string()
}

///|
/// Retains /prefix even for IPv4-mapped IPv6 (Python 3.13.2 drops it).
pub fn IpInterface::exploded(self : IpInterface) -> String {
  "\{self.ip().exploded()}/\{self.prefixlen()}"
}

///|
/// Explicit prefix/mask variants omit the scope, matching Python's interface
/// properties; to_string()/compressed() retain it.
pub fn IpInterface::with_prefixlen(self : IpInterface) -> String {
  "\{self.address_.as_address()}/\{self.prefixlen()}"
}

///|
pub fn IpInterface::with_netmask(self : IpInterface) -> String {
  "\{self.address_.as_address()}/\{self.netmask()}"
}

///|
pub fn IpInterface::with_hostmask(self : IpInterface) -> String {
  "\{self.address_.as_address()}/\{self.hostmask()}"
}

///|
pub fn IpInterface::to_bigint(self : IpInterface) -> @bigint.BigInt {
  self.address_.to_bigint()
}

///|
pub fn IpInterface::to_bytes(self : IpInterface) -> Bytes {
  self.address_.to_bytes()
}

///|
pub fn IpInterface::format(
  self : IpInterface,
  spec : String,
) -> String raise IpError {
  if spec == "" || spec.has_suffix("s") {
    ip_format_string(self.to_string(), spec)
  } else {
    self.address_.format(spec)
  }
}

///|
pub fn IpInterface::add(
  self : IpInterface,
  amount : @bigint.BigInt,
) -> IpInterface raise IpError {
  IpInterface::from_address(self.address_.add(amount), self.max_prefixlen())
}

///|
pub fn IpInterface::subtract(
  self : IpInterface,
  amount : @bigint.BigInt,
) -> IpInterface raise IpError {
  IpInterface::from_address(
    self.address_.subtract(amount),
    self.max_prefixlen(),
  )
}

///|
/// Reverse-DNS name of the host address, without interface prefix or scope.
pub fn IpInterface::reverse_pointer(self : IpInterface) -> String {
  self.ip().reverse_pointer()
}

///|
pub fn IpInterface::is_private(self : IpInterface) -> Bool {
  self.address_.is_private()
}

///|
pub fn IpInterface::is_global(self : IpInterface) -> Bool {
  self.address_.is_global()
}

///|
pub fn IpInterface::is_reserved(self : IpInterface) -> Bool {
  self.address_.is_reserved()
}

///|
pub fn IpInterface::is_multicast(self : IpInterface) -> Bool {
  self.address_.is_multicast()
}

///|
/// Python 3.13.2 treats IPv4 interfaces as distinct from the bare unspecified
/// address, so this is false for IPv4; use ip().is_unspecified() for host-only
/// classification. IPv6 requires both the host and network to be unspecified.
pub fn IpInterface::is_unspecified(self : IpInterface) -> Bool {
  self.family() == V6 &&
  self.address_.to_bigint() == 0N &&
  self.network_.is_unspecified()
}

///|
pub fn IpInterface::is_loopback(self : IpInterface) -> Bool {
  self.address_.is_loopback() &&
  (self.family() == V4 || self.network_.is_loopback())
}

///|
pub fn IpInterface::is_link_local(self : IpInterface) -> Bool {
  self.address_.is_link_local()
}

///|
pub fn IpInterface::is_site_local(self : IpInterface) -> Bool {
  self.address_.is_site_local()
}

///|
pub fn IpInterface::ipv4_mapped(self : IpInterface) -> IpAddress? {
  self.address_.ipv4_mapped()
}

///|
pub fn IpInterface::ipv6_mapped(self : IpInterface) -> IpAddress? {
  self.address_.ipv6_mapped()
}

///|
pub fn IpInterface::sixtofour(self : IpInterface) -> IpAddress? {
  self.address_.sixtofour()
}

///|
pub fn IpInterface::teredo(self : IpInterface) -> (IpAddress, IpAddress)? {
  self.address_.teredo()
}

///|
pub extend IpInterface with @debug.Debug::{to_repr}

///|
pub impl @debug.Debug for IpInterface with fn to_repr(self) {
  @debug.Repr(self.to_string())
}
