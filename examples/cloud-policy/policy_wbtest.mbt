///|
test "real EC2 policy agrees with netaddr 1.3.0" {
  assert_eq(run(), @json.parse(expected_result))
}

///|
test "exclusions are disjoint and coverage is conserved" {
  let all = @net.IpSet::from_cidrs(lines(source_prefixes))
  let exceptions = @net.IpSet::from_cidrs(lines(exception_prefixes))
  let allowed = all.difference(exceptions)
  assert_false(allowed.overlaps(exceptions))
  assert_true(allowed.union(all.intersection(exceptions)) == all)
  assert_true(exceptions.is_subset_of(all))
}
