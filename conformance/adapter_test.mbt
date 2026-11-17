// Public, test-only request adapter over the library API; no host I/O.

///|
suberror RequestError {
  Invalid
}

///|
fn field(r : Json, key : String) -> Json? {
  match r {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn text(r : Json, key : String) -> String raise RequestError {
  match field(r, key) {
    Some(String(s)) => s
    _ => raise Invalid
  }
}

///|
fn integer(
  r : Json,
  key : String,
  default~ : Int32 = 0,
) -> Int32 raise RequestError {
  match field(r, key) {
    Some(Number(n, ..)) => {
      let i = n.to_int()
      if i.to_double() != n {
        raise Invalid
      }
      i
    }
    None => default
    _ => raise Invalid
  }
}

///|
fn boolean(
  r : Json,
  key : String,
  default~ : Bool = false,
) -> Bool raise RequestError {
  match field(r, key) {
    Some(True) => true
    Some(False) => false
    None => default
    _ => raise Invalid
  }
}

///|
fn big(r : Json, key : String) -> BigInt raise RequestError {
  let s = text(r, key)
  if s.is_empty() || s == "-" {
    raise Invalid
  }
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int()
    if !(i == 0 && ch == 45) && (ch < 48 || ch > 57) {
      raise Invalid
    }
  }
  @string.parse_bigint(s) catch {
    _ => raise Invalid
  }
}

///|
fn packed(r : Json) -> Bytes raise RequestError {
  let items = match field(r, "bytes") {
    Some(Array(a)) => a
    _ => raise Invalid
  }
  let bytes : Array[Byte] = []
  for item in items {
    match item {
      Number(n, ..) => {
        let i = n.to_int()
        if i < 0 || i > 255 || i.to_double() != n {
          raise Invalid
        }
        bytes.push(i.to_byte())
      }
      _ => raise Invalid
    }
  }
  Bytes::from_array(bytes[:])
}

///|
fn strings(r : Json, key : String) -> Array[String] raise RequestError {
  let items = match field(r, key) {
    Some(Array(a)) => a
    _ => raise Invalid
  }
  items.map(item => {
    match item {
      String(s) => s
      _ => raise Invalid
    }
  })
}

///|
fn js(s : String) -> Json {
  Json::string(s)
}

///|
fn jb(b : Bool) -> Json {
  Json::boolean(b)
}

///|
fn jn(n : Int32) -> Json {
  Json::number(n.to_double())
}

///|
fn opt(s : String?) -> Json {
  match s {
    Some(s) => js(s)
    None => Json::null()
  }
}

///|
fn address_opt(a : @net.IpAddress?) -> Json {
  match a {
    Some(a) => js(a.to_string())
    None => Json::null()
  }
}

///|
fn byte_json(bytes : Bytes) -> Json {
  Json::array(bytes.to_array().map(b => jn(b.to_int())))
}

///|
fn address_json(v : @net.IpAddress) -> Json {
  Json::object({
    "text": js(v.to_string()),
    "compressed": js(v.compressed()),
    "integer": js(v.to_bigint().to_string()),
    "version": jn(v.version()),
    "max_prefixlen": jn(v.max_prefixlen()),
    "is_private": jb(v.is_private()),
    "is_global": jb(v.is_global()),
    "is_reserved": jb(v.is_reserved()),
    "is_multicast": jb(v.is_multicast()),
    "is_unspecified": jb(v.is_unspecified()),
    "is_loopback": jb(v.is_loopback()),
    "is_link_local": jb(v.is_link_local()),
    "is_site_local": jb(v.is_site_local()),
    "scope_id": opt(v.scope_id()),
    "packed": byte_json(v.to_bytes()),
    "ipv4_mapped": address_opt(v.ipv4_mapped()),
    "ipv6_mapped": address_opt(v.ipv6_mapped()),
    "sixtofour": address_opt(v.sixtofour()),
    "teredo": match v.teredo() {
      None => Json::null()
      Some((server, client)) =>
        Json::array([js(server.to_string()), js(client.to_string())])
    },
  })
}

///|
fn network_json(v : @net.IpNetwork) -> Json {
  Json::object({
    "text": js(v.to_string()),
    "compressed": js(v.compressed()),
    "network_address": js(v.network_address().to_string()),
    "broadcast_address": js(v.broadcast_address().to_string()),
    "netmask": js(v.netmask().to_string()),
    "hostmask": js(v.hostmask().to_string()),
    "num_addresses": js(v.num_addresses().to_string()),
    "with_prefixlen": js(v.with_prefixlen()),
    "with_netmask": js(v.with_netmask()),
    "with_hostmask": js(v.with_hostmask()),
    "version": jn(v.version()),
    "max_prefixlen": jn(v.max_prefixlen()),
    "prefixlen": jn(v.prefixlen()),
    "is_private": jb(v.is_private()),
    "is_global": jb(v.is_global()),
    "is_reserved": jb(v.is_reserved()),
    "is_multicast": jb(v.is_multicast()),
    "is_unspecified": jb(v.is_unspecified()),
    "is_loopback": jb(v.is_loopback()),
    "is_link_local": jb(v.is_link_local()),
    "is_site_local": jb(v.is_site_local()),
  })
}

///|
fn interface_json(v : @net.IpInterface) -> Json {
  Json::object({
    "text": js(v.to_string()),
    "compressed": js(v.compressed()),
    "ip": js(v.ip().to_string()),
    "address": js(v.address().to_string()),
    "network": js(v.network().to_string()),
    "netmask": js(v.netmask().to_string()),
    "hostmask": js(v.hostmask().to_string()),
    "with_prefixlen": js(v.with_prefixlen()),
    "with_netmask": js(v.with_netmask()),
    "with_hostmask": js(v.with_hostmask()),
    "integer": js(v.address().to_bigint().to_string()),
    "version": jn(v.version()),
    "max_prefixlen": jn(v.max_prefixlen()),
    "prefixlen": jn(v.prefixlen()),
    "is_private": jb(v.is_private()),
    "is_global": jb(v.is_global()),
    "is_reserved": jb(v.is_reserved()),
    "is_multicast": jb(v.is_multicast()),
    "is_unspecified": jb(v.is_unspecified()),
    "is_loopback": jb(v.is_loopback()),
    "is_link_local": jb(v.is_link_local()),
    "is_site_local": jb(v.is_site_local()),
    "scope_id": opt(v.address().scope_id()),
    "packed": byte_json(v.address().to_bytes()),
  })
}

///|
fn address_int(r : Json) -> @net.IpAddress raise {
  let value = big(r, "value")
  match integer(r, "family") {
    0 => @net.IpAddress::from_bigint(value)
    4 => @net.IpAddress::from_bigint(value, family=@net.V4)
    6 => @net.IpAddress::from_bigint(value, family=@net.V6)
    _ => raise Invalid
  }
}

///|
fn network_int(r : Json) -> @net.IpNetwork raise {
  let value = big(r, "value")
  let address = address_int(r)
  let prefix = integer(r, "prefix", default=address.max_prefixlen())
  @net.IpNetwork::from_bigint(value, prefix~, family=address.family())
}

///|
fn interface_int(r : Json) -> @net.IpInterface raise {
  let value = big(r, "value")
  let address = address_int(r)
  let prefix = integer(r, "prefix", default=address.max_prefixlen())
  @net.IpInterface::from_bigint(value, prefix~, family=address.family())
}

///|
fn address_array(values : Iter[@net.IpAddress], count : Int32) -> Json {
  Json::array(values.take(count).map(v => js(v.to_string())).to_array())
}

///|
fn network_array(values : Iter[@net.IpNetwork], count : Int32) -> Json {
  Json::array(values.take(count).map(v => js(v.to_string())).to_array())
}

///|
fn[T : Eq + Hash + Compare] identity(a : T, b : T) -> Json {
  let values : Map[T, Int32] = Map([])
  values[a] = 7
  Json::object({
    "equal": jb(a == b),
    "less": jb(a < b),
    "greater": jb(a > b),
    "equal_implies_same_hash": jb(a != b || Hash::hash(a) == Hash::hash(b)),
    "lookup": match values.get(b) {
      Some(v) => jn(v)
      None => Json::null()
    },
  })
}

///|
fn ip_input(r : Json) -> @net.IpInput raise {
  match text(r, "kind") {
    "address" => @net.AddressInput(@net.ip_address(text(r, "text")))
    "network" => @net.NetworkInput(@net.ip_network(text(r, "text")))
    "interface" => @net.InterfaceInput(@net.ip_interface(text(r, "text")))
    _ => raise Invalid
  }
}

///|
fn evaluate(r : Json) -> Json raise {
  match text(r, "op") {
    "address" => address_json(@net.ip_address(text(r, "text")))
    "address_int" => address_json(address_int(r))
    "address_bytes" => address_json(@net.IpAddress::from_bytes(packed(r)))
    "address_op" => {
      let a = @net.ip_address(text(r, "text"))
      js(
        match text(r, "action") {
          "expanded" => a.exploded()
          "reverse" => a.reverse_pointer()
          "format" => a.format(text(r, "format"))
          "add" => a.add(big(r, "offset")).to_string()
          "subtract" => a.subtract(big(r, "offset")).to_string()
          _ => raise Invalid
        },
      )
    }
    "address_compare" => {
      let a = @net.ip_address(text(r, "left"))
      let b = @net.ip_address(text(r, "right"))
      Json::object({
        "equal": jb(a == b),
        "less": jb(a < b),
        "greater": jb(a > b),
      })
    }
    "network" =>
      network_json(
        @net.ip_network(
          text(r, "text"),
          strict=boolean(r, "strict", default=true),
        ),
      )
    "network_int" => network_json(network_int(r))
    "network_from_address_mask" =>
      network_json(
        @net.IpNetwork::from_address_mask(
          @net.ip_address(text(r, "address")),
          text(r, "mask"),
          strict=boolean(r, "strict", default=true),
        ),
      )
    "network_bytes" => {
      let bytes = packed(r)
      network_json(
        @net.IpNetwork::from_bytes(
          bytes,
          prefix=integer(r, "prefix", default=bytes.length() * 8),
        ),
      )
    }
    "network_op" => {
      let n = @net.ip_network(text(r, "text"))
      let limit = integer(r, "limit", default=4)
      let diff = integer(r, "diff", default=1)
      match text(r, "action") {
        "iter" => address_array(n.iter(), limit)
        "hosts" => address_array(n.hosts(), limit)
        "nth" => js(n.nth(big(r, "index")).to_string())
        "subnets" => {
          let items = match field(r, "new_prefix") {
            None => n.subnets(prefixlen_diff=diff)
            Some(_) =>
              n.subnets(
                prefixlen_diff=diff,
                new_prefix=integer(r, "new_prefix"),
              )
          }
          network_array(items, limit)
        }
        "supernet" =>
          js(
            match field(r, "new_prefix") {
              None => n.supernet(prefixlen_diff=diff).to_string()
              Some(_) =>
                n
                .supernet(
                  prefixlen_diff=diff,
                  new_prefix=integer(r, "new_prefix"),
                )
                .to_string()
            },
          )
        "contains" => jb(n.contains(@net.ip_address(text(r, "other"))))
        "overlaps" => jb(n.overlaps(@net.ip_network(text(r, "other"))))
        "subnet_of" => jb(n.subnet_of(@net.ip_network(text(r, "other"))))
        "supernet_of" => jb(n.supernet_of(@net.ip_network(text(r, "other"))))
        "compare_networks" =>
          jn(n.compare_networks(@net.ip_network(text(r, "other"))))
        "exclude" =>
          network_array(
            n.address_exclude(@net.ip_network(text(r, "other"))),
            limit,
          )
        "expanded" => js(n.exploded())
        _ => raise Invalid
      }
    }
    "interface_from_address_mask" =>
      interface_json(
        @net.IpInterface::from_address_mask(
          @net.ip_address(text(r, "address")),
          text(r, "mask"),
        ),
      )
    "interface" => interface_json(@net.ip_interface(text(r, "text")))
    "interface_int" => interface_json(interface_int(r))
    "interface_bytes" => {
      let bytes = packed(r)
      interface_json(
        @net.IpInterface::from_bytes(
          bytes,
          prefix=integer(r, "prefix", default=bytes.length() * 8),
        ),
      )
    }
    "interface_expanded" => js(@net.ip_interface(text(r, "text")).exploded())
    "interface_op" => {
      let a = @net.ip_interface(text(r, "text"))
      match text(r, "action") {
        "expanded" => js(a.exploded())
        "reverse" => js(a.reverse_pointer())
        "format" => js(a.format(text(r, "format")))
        "add" => js(a.add(big(r, "offset")).to_string())
        "subtract" => js(a.subtract(big(r, "offset")).to_string())
        "ipv4_mapped" => address_opt(a.ipv4_mapped())
        "ipv6_mapped" => address_opt(a.ipv6_mapped())
        "sixtofour" => address_opt(a.sixtofour())
        "teredo" =>
          match a.teredo() {
            None => Json::null()
            Some((s, c)) => Json::array([js(s.to_string()), js(c.to_string())])
          }
        _ => raise Invalid
      }
    }
    "identity" => {
      let left = text(r, "left")
      let right = text(r, "right")
      match text(r, "kind") {
        "address" => identity(@net.ip_address(left), @net.ip_address(right))
        "network" => identity(@net.ip_network(left), @net.ip_network(right))
        "interface" =>
          identity(@net.ip_interface(left), @net.ip_interface(right))
        _ => raise Invalid
      }
    }
    "address_packed" =>
      byte_json(
        match integer(r, "family") {
          4 => @net.v4_int_to_packed(big(r, "value"))
          6 => @net.v6_int_to_packed(big(r, "value"))
          _ => raise Invalid
        },
      )
    "parse_family" => {
      let t = text(r, "text")
      let v4 = match integer(r, "family") {
        4 => true
        6 => false
        _ => raise Invalid
      }
      match text(r, "kind") {
        "address" =>
          address_json(
            if v4 {
              @net.ipv4_address(t)
            } else {
              @net.ipv6_address(t)
            },
          )
        "network" =>
          network_json(
            if v4 {
              @net.ipv4_network(t)
            } else {
              @net.ipv6_network(t)
            },
          )
        "interface" =>
          interface_json(
            if v4 {
              @net.ipv4_interface(t)
            } else {
              @net.ipv6_interface(t)
            },
          )
        _ => raise Invalid
      }
    }
    "address_unscoped" =>
      address_json(@net.ip_address(text(r, "text")).unscoped())
    "address_roundtrip" =>
      address_json(
        @net.IpAddress::from_address(
          @net.ip_address(text(r, "text")).as_address(),
        ),
      )
    "network_roundtrip" =>
      network_json(
        @net.IpNetwork::from_cidr(@net.ip_network(text(r, "text")).as_cidr()),
      )
    "mixed_key" => {
      let item = match field(r, "item") {
        Some(v) => v
        None => raise Invalid
      }
      let key = @net.get_mixed_type_key(ip_input(item))
      Json::array([jn(key.0), js(key.1.to_string()), jn(key.2)])
    }
    "collapse_inputs" => {
      let items = match field(r, "items") {
        Some(Array(v)) => v
        _ => raise Invalid
      }
      Json::array(
        @net.collapse_ip_inputs(items.map(ip_input)).map(v => js(v.to_string())),
      )
    }
    "mixed_sort" => {
      let items = match field(r, "items") {
        Some(Array(v)) => v
        _ => raise Invalid
      }
      let inputs = items.map(ip_input)
      let order = Array::makei(inputs.length(), i => i)
      order.sort_by((a, b) => {
        let compared = @net.get_mixed_type_key(inputs[a]).compare(
          @net.get_mixed_type_key(inputs[b]),
        )
        if compared == 0 {
          a.compare(b)
        } else {
          compared
        }
      })
      Json::array(order.map(jn))
    }
    "summarize" =>
      Json::array(
        @net.summarize_address_range(
          @net.ip_address(text(r, "first")),
          @net.ip_address(text(r, "last")),
        ).map(v => js(v.to_string())),
      )
    "collapse" =>
      Json::array(
        @net.collapse_addresses(
          strings(r, "items").map(t => @net.ip_network(t)),
        ).map(v => js(v.to_string())),
      )
    _ => raise Invalid
  }
}
