///|
/// A canonical CIDR network; host bits are zero and the prefix fits the family.
struct Cidr {
  network_ : Address
  prefix_ : Int32
} derive(Eq)

///|
pub extend Cidr with Eq::{equal, not_equal}

///|
pub extend Cidr with Show::{output}

///|
/// Constructs a CIDR, clearing host bits unless strict validation is requested.
pub fn Cidr::new(
  address : Address,
  prefix : Int32,
  strict~ : Bool = false,
) -> Cidr raise IpError {
  if prefix < 0 || prefix > address.width() {
    raise InvalidPrefix("\{address}/\{prefix}")
  }
  let network = address.mask(prefix)
  if strict && network != address {
    raise HostBitsSet("\{address}/\{prefix}")
  }
  { network_: network, prefix_: prefix, }
}

///|
/// Parses address/prefix syntax. The prefix uses decimal digits without leading zeros.
pub fn Cidr::parse(text : String, strict~ : Bool = false) -> Cidr raise IpError {
  let (address_text, prefix_text) = match text.split_once("/") {
    Some(parts) => parts
    None => raise InvalidPrefix(text)
  }
  if prefix_text.is_empty() || prefix_text.length() > 3 {
    raise InvalidPrefix(text)
  }
  if prefix_text.length() > 1 && prefix_text[0].to_int() == 48 {
    raise InvalidPrefix(text)
  }
  let mut prefix = 0
  for unit in prefix_text.code_units() {
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 {
      raise InvalidPrefix(text)
    }
    prefix = prefix * 10 + digit
  }
  Cidr::new(Address::parse(address_text.to_owned()), prefix, strict~)
}

///|
/// The first address of this network.
pub fn Cidr::network(self : Cidr) -> Address {
  self.network_
}

///|
/// The inclusive final address of this network.
pub fn Cidr::last(self : Cidr) -> Address {
  self.network_.block_end(self.prefix_)
}

///|
/// Number of leading network bits.
pub fn Cidr::prefix(self : Cidr) -> Int32 {
  self.prefix_
}

///|
/// Canonical network address followed by a decimal prefix.
pub fn Cidr::to_string(self : Cidr) -> String {
  "\{self.network_.to_string()}/\{self.prefix_}"
}

///|
pub impl Show for Cidr with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
// Internal: caller guarantees an aligned network and a prefix in the family range.
fn cidr_from_normalized(address : Address, prefix : Int32) -> Cidr {
  { network_: address, prefix_: prefix, }
}
