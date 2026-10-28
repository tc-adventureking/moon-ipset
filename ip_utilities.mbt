///|
/// Explicitly distinguish host addresses, interfaces and networks for mixed
/// operations. An interface contributes its host address, not its subnet.
pub(all) enum IpInput {
  AddressInput(IpAddress)
  InterfaceInput(IpInterface)
  NetworkInput(IpNetwork)
} derive(Eq)

///|
pub extend IpInput with Eq::{equal, not_equal}

///|
pub extend IpInput with Show::{output, to_string}

///|
pub impl Show for IpInput with fn output(self, logger) {
  match self {
    AddressInput(address) => logger.write_string(address.to_string())
    InterfaceInput(interface) => logger.write_string(interface.to_string())
    NetworkInput(network) => logger.write_string(network.to_string())
  }
}

///|
/// Numeric mixed sort key: version, address value, then -1 for a host or the
/// network prefix length. Hosts precede networks with the same base address;
/// broader networks precede narrower ones with that same base. For unscoped
/// addresses and networks this reproduces Python's ordering. Zone identifiers are not
/// part of this numeric key; equal keys do not imply identical scoped objects.
/// Interfaces use their host value and ignore the prefix. Python's comparison
/// between two Interface objects can instead compare their networks first.
pub fn get_mixed_type_key(input : IpInput) -> (Int32, @bigint.BigInt, Int32) {
  match input {
    AddressInput(address) => (address.version(), address.to_bigint(), -1)
    InterfaceInput(interface) =>
      (interface.version(), interface.address().to_bigint(), -1)
    NetworkInput(network) =>
      (
        network.version(),
        network.network_address().to_bigint(),
        network.prefixlen(),
      )
  }
}

///|
/// Minimal CIDR cover of hosts, interfaces and networks from one family.
/// Hosts and interface hosts become /32 or /128 networks, ignoring interface
/// prefixes. Like collapse_addresses, the output is a canonical
/// numeric cover: IPv6 zones are discarded, never used to merge address bits.
pub fn collapse_ip_inputs(
  inputs : Array[IpInput],
) -> Array[IpNetwork] raise IpError {
  let networks : Array[IpNetwork] = []
  for input in inputs {
    match input {
      AddressInput(address) =>
        networks.push(
          IpNetwork::from_address(address.unscoped(), address.max_prefixlen()),
        )
      InterfaceInput(interface) =>
        networks.push(
          IpNetwork::from_address(interface.ip(), interface.max_prefixlen()),
        )
      NetworkInput(network) => networks.push(network)
    }
  }
  collapse_addresses(networks)
}
