///|
// Generate fixed packed inputs before timing; parsing and fixture checks are not
// part of the measurement. Each iteration converts a whole batch.
fn packed_fixture(width : Int32, count : Int32) -> Array[Bytes] {
  let mut state = Seed
  Array::makei(count, i => {
    Bytes::makei(width, _ => {
      state = state * 1664525U + 1013904223U
      if i == 0 {
        b'\x00'
      } else if i == 1 {
        b'\xff'
      } else {
        (state >> 24).to_byte()
      }
    })
  })
}

///|
fn packed_address(bytes : Bytes) -> @ipset.IpAddress {
  @ipset.IpAddress::from_bytes(bytes) catch {
    error => abort("invalid packed benchmark fixture: \{error}")
  }
}

///|
fn[T] measure_packed(
  family : String,
  count : Int32,
  operation : String,
  samples : UInt32,
  operation_fn : () -> T,
) -> Unit {
  let benchmark = @benchmark.Bench()
  benchmark.bench(
    () => benchmark.keep(operation_fn()),
    name="packed.\{family}.\{operation}.n\{count}",
    count=samples,
  )
  println(
    "{\"family\":\"\{family}\",\"addresses_per_iteration\":\{count},\"seed\":\{Seed},\"operation\":\"\{operation}\",\"unit\":\"microseconds_per_batch\",\"summaries\":\{benchmark.dump_summaries()}}",
  )
}

///|
fn run_packed_suite(smoke : Bool) -> Unit {
  let count = if smoke { 16 } else { 256 }
  let samples = if smoke { 2U } else { 7U }
  for (family, width) in [("ipv4", 4), ("ipv6", 16)] {
    let packed = packed_fixture(width, count)
    let addresses = packed.map(packed_address)
    for i = 0; i < count; i = i + 1 {
      if addresses[i].to_bytes() != packed[i] ||
        addresses[i].max_prefixlen() != width * 8 {
        abort("packed benchmark fixture round trip failed")
      }
    }
    measure_packed(family, count, "from_bytes", samples, () => {
      packed.map(packed_address)
    })
    measure_packed(family, count, "to_bytes", samples, () => {
      addresses.map(address => address.to_bytes())
    })
  }
}
