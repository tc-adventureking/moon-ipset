///|
// Fixed fixtures are generated outside timed regions. No address space is enumerated.
const Seed : UInt32 = 0x5eed2026U

///|
fn v4(value : Int32) -> String {
  "10.\{(value >> 16) & 255}.\{(value >> 8) & 255}.\{value & 255}"
}

///|
fn v6(value : Int32) -> String {
  let high = (value >> 16).reinterpret_as_uint().to_string(radix=16)
  let low = (value & 65535).reinterpret_as_uint().to_string(radix=16)
  "2001:db8::\{high}:\{low}"
}

///|
fn shuffled(values : Array[String]) -> Array[String] {
  let result = values.copy()
  let mut state = Seed
  let mut i = result.length() - 1
  while i > 0 {
    state = state * 1664525U + 1013904223U
    let j = (state % (i + 1).reinterpret_as_uint()).reinterpret_as_int()
    let tmp = result[i]
    result[i] = result[j]
    result[j] = tmp
    i = i - 1
  }
  result
}

///|
fn fixture(profile : String, count : Int32) -> (Array[String], Array[String]) {
  let left = []
  let right = []
  for i = 0; i < count; i = i + 1 {
    match profile {
      "overlap" => {
        let base = i % 16 * 512
        left.push("\{v4(base)}/\{24 + i % 3}")
        right.push("\{v4(base + 128)}/25")
      }
      "discrete" => {
        left.push("\{v4(i * 4)}/32")
        right.push("\{v4(i * 4 + 2)}/32")
      }
      "fragmented" => {
        left.push("\{v4(i * 512)}/24")
        right.push("\{v4(i * 512 + 64)}/26")
      }
      "mixed" =>
        if i % 2 == 0 {
          left.push("\{v4(i * 512)}/24")
          right.push("\{v4(i * 512 + 64)}/26")
        } else {
          left.push("\{v6(i * 512)}/120")
          right.push("\{v6(i * 512 + 64)}/122")
        }
      _ => abort("unknown fixture profile")
    }
  }
  (shuffled(left), shuffled(right))
}

///|
fn normalized(values : Array[String]) -> @ipset.IpSet {
  @ipset.IpSet::from_cidrs(values) catch {
    error => abort("invalid benchmark fixture: \{error}")
  }
}

///|
fn query_fixture(
  values : Array[String],
  count : Int32,
) -> Array[@ipset.Address] {
  let queries = []
  for i = 0; i < count; i = i + 1 {
    let cidr = @ipset.Cidr::parse(values[i % values.length()]) catch {
      error => abort("invalid benchmark query: \{error}")
    }
    queries.push(
      if i % 2 == 0 {
        cidr.network()
      } else {
        match cidr.last().next() {
          Some(next) => next
          None => cidr.last()
        }
      },
    )
  }
  queries
}

///|
fn contains_batch(set : @ipset.IpSet, queries : Array[@ipset.Address]) -> Int32 {
  let mut hits = 0
  for query in queries {
    if set.contains(query) {
      hits = hits + 1
    }
  }
  hits
}

///|
fn optional_int(value : Int32?) -> String {
  match value {
    Some(number) => number.to_string()
    None => "null"
  }
}

///|
fn[T] measure(
  profile : String,
  input_count : Int32,
  operation : String,
  left_intervals : Int32,
  right_intervals : Int32,
  output_intervals : Int32?,
  output_cidrs : Int32?,
  queries : Int32,
  hits : Int32?,
  samples : UInt32,
  operation_fn : () -> T,
) -> Unit {
  let benchmark = @benchmark.Bench()
  benchmark.bench(
    () => benchmark.keep(operation_fn()),
    name="\{profile}.\{operation}.n\{input_count}",
    count=samples,
  )
  println(
    "{\"profile\":\"\{profile}\",\"input_count_per_operand\":\{input_count},\"seed\":\{Seed},\"operation\":\"\{operation}\",\"left_intervals\":\{left_intervals},\"right_intervals\":\{right_intervals},\"output_intervals\":\{optional_int(output_intervals)},\"output_cidrs\":\{optional_int(output_cidrs)},\"queries_per_iteration\":\{queries},\"hits\":\{optional_int(hits)},\"unit\":\"microseconds_per_iteration\",\"summaries\":\{benchmark.dump_summaries()}}",
  )
}

///|
fn run_case(
  profile : String,
  count : Int32,
  samples : UInt32,
  smoke : Bool,
) -> Unit {
  let (raw_left, raw_right) = fixture(profile, count)
  let left = normalized(raw_left)
  let right = normalized(raw_right)
  let union = left.union(right)
  let difference = left.difference(right)
  let query_count = if smoke { 128 } else { 1024 }
  let queries = query_fixture(raw_left, query_count)
  let left_size = left.intervals().length()
  let right_size = right.intervals().length()
  measure(
    profile,
    count,
    "parse_normalize",
    left_size,
    right_size,
    Some(left_size),
    Some(left.cidrs().length()),
    0,
    None,
    samples,
    () => normalized(raw_left),
  )
  measure(
    profile,
    count,
    "union",
    left_size,
    right_size,
    Some(union.intervals().length()),
    Some(union.cidrs().length()),
    0,
    None,
    samples,
    () => left.union(right),
  )
  measure(
    profile,
    count,
    "difference",
    left_size,
    right_size,
    Some(difference.intervals().length()),
    Some(difference.cidrs().length()),
    0,
    None,
    samples,
    () => left.difference(right),
  )
  // The precomputed difference is used so fragmented inputs expose cover cost.
  measure(
    profile,
    count,
    "cidrs_of_difference",
    left_size,
    right_size,
    Some(difference.intervals().length()),
    Some(difference.cidrs().length()),
    0,
    None,
    samples,
    () => difference.cidrs(),
  )
  measure(
    profile,
    count,
    "contains_batch",
    left_size,
    right_size,
    None,
    None,
    query_count,
    Some(contains_batch(left, queries)),
    samples,
    () => contains_batch(left, queries),
  )
}

///|
fn main {
  let smoke = @env.args().contains("--smoke")
  if @env.args().contains("--subset") {
    run_subset_suite(smoke)
    return
  }
  let sizes = if smoke { [100] } else { [100, 1000, 10000] }
  let profiles = if smoke {
    ["mixed"]
  } else {
    ["overlap", "discrete", "fragmented", "mixed"]
  }
  for count in sizes {
    for profile in profiles {
      run_case(profile, count, if smoke { 2U } else { 5U }, smoke)
    }
  }
}
