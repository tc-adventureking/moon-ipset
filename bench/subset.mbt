///|
// Alternate address families; every singleton remains a separate interval.
// Covering /31 and /127 blocks are wider than each left-hand singleton.
fn subset_fixture(
  scenario : String,
  count : Int32,
) -> (@ipset.IpSet, @ipset.IpSet) {
  let left = []
  let right = []
  for i = 0; i < count; i = i + 1 {
    let (address, singleton_prefix, covering_prefix) = if i % 2 == 0 {
      (v4(i * 4), 32, 31)
    } else {
      (v6(i * 4), 128, 127)
    }
    left.push("\{address}/\{singleton_prefix}")
    let omit = match scenario {
      "empty_right" => true
      "first_uncovered" => i == 0
      "last_uncovered" => i == count - 1
      "covered" => false
      _ => abort("unknown subset scenario")
    }
    if !omit {
      right.push("\{address}/\{covering_prefix}")
    }
  }
  (normalized(shuffled(left)), normalized(shuffled(right)))
}

///|
fn measure_subset(
  scenario : String,
  count : Int32,
  left_intervals : Int32,
  right_intervals : Int32,
  implementation : String,
  expected : Bool,
  samples : UInt32,
  operation_fn : () -> Bool,
) -> Unit {
  // These are fixture assertions, deliberately outside the timed closure.
  let actual = operation_fn()
  if actual != expected {
    abort("wrong subset result: \{scenario}/\{implementation}")
  }
  let benchmark = @benchmark.Bench()
  benchmark.bench(
    () => benchmark.keep(operation_fn()),
    name="subset.\{scenario}.\{implementation}.n\{count}",
    count=samples,
  )
  println(
    "{\"scenario\":\"\{scenario}\",\"left_input_count\":\{count},\"seed\":\{Seed},\"implementation\":\"\{implementation}\",\"left_intervals\":\{left_intervals},\"right_intervals\":\{right_intervals},\"expected\":\{expected},\"actual\":\{actual},\"unit\":\"microseconds_per_iteration\",\"summaries\":\{benchmark.dump_summaries()}}",
  )
}

///|
fn run_subset_suite(smoke : Bool) -> Unit {
  let sizes = if smoke { [100] } else { [100, 1000, 10000] }
  let scenarios = [
    "empty_right", "first_uncovered", "last_uncovered", "covered",
  ]
  for count in sizes {
    for scenario in scenarios {
      let (left, right) = subset_fixture(scenario, count)
      let left_size = left.intervals().length()
      let right_size = right.intervals().length()
      let expected_right_size = match scenario {
        "empty_right" => 0
        "covered" => count
        _ => count - 1
      }
      if left_size != count || right_size != expected_right_size {
        abort("unexpected subset fixture interval counts")
      }
      let expected = scenario == "covered"
      let samples = if smoke { 2U } else { 5U }
      measure_subset(
        scenario,
        count,
        left_size,
        right_size,
        "is_subset_of",
        expected,
        samples,
        () => left.is_subset_of(right),
      )
      measure_subset(
        scenario,
        count,
        left_size,
        right_size,
        "difference_is_empty",
        expected,
        samples,
        () => left.difference(right).is_empty(),
      )
    }
  }
}
