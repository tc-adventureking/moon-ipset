///|
/// An inclusive interval in exactly one IP address family.
/// Construct with `Interval::new`; endpoints cannot be changed afterwards.
pub struct Interval {
  priv lo : Address
  priv hi : Address
} derive(Eq)

///|
pub extend Interval with Eq::{not_equal, equal}

///|
/// Validate and create an inclusive address interval.
pub fn Interval::new(first : Address, last : Address) -> Interval raise IpError {
  if first.family() != last.family() {
    raise InvalidRange("range endpoints must belong to the same address family")
  }
  if first > last {
    raise InvalidRange("range start must not be greater than range end")
  }
  { lo: first, hi: last, }
}

///|
/// Return the first address, including that address in the range.
pub fn Interval::first(self : Interval) -> Address {
  self.lo
}

///|
/// Return the last address, including that address in the range.
pub fn Interval::last(self : Interval) -> Address {
  self.hi
}

///|
/// An immutable set of IPv4 and/or IPv6 addresses.
/// Intervals are sorted, non-overlapping, and non-adjacent within each family.
/// IPv4 and IPv6 (including IPv4-mapped IPv6 addresses) remain distinct.
pub struct IpSet {
  priv ranges : Array[Interval]
} derive(Eq)

///|
pub extend IpSet with Eq::{not_equal, equal}

///|
/// Create a set with no addresses.
pub fn IpSet::empty() -> IpSet {
  { ranges: [], }
}

///|
/// Parse and combine CIDR networks, normalizing any host bits in the input.
/// One invalid CIDR rejects the entire construction.
pub fn IpSet::from_cidrs(cidrs : Array[String]) -> IpSet raise IpError {
  let ranges = []
  for text in cidrs {
    let cidr = Cidr::parse(text)
    ranges.push({ lo: cidr.network(), hi: cidr.last(), })
  }
  IpSet::from_ranges(ranges)
}

///|
/// Append an interval to a sorted sequence, merging overlap and adjacency.
/// The input must not precede the last stored interval. Family boundaries never
/// merge. In particular, maximum-address adjacency never wraps to address zero.
fn append_canonical(output : Array[Interval], item : Interval) -> Unit {
  let count = output.length()
  if count == 0 {
    output.push(item)
    return
  }
  let previous = output[count - 1]
  let same_family = previous.lo.family() == item.lo.family()
  let touches = previous.hi >= item.lo ||
    (match previous.hi.next() {
      Some(next) => next == item.lo
      None => false
    })
  if same_family && touches {
    if item.hi > previous.hi {
      output[count - 1] = { lo: previous.lo, hi: item.hi, }
    }
  } else {
    output.push(item)
  }
}

///|
/// Canonicalize a collection of valid intervals. The caller's array is copied
/// before sorting; subsequent mutations of it cannot change this set.
pub fn IpSet::from_ranges(ranges : Array[Interval]) -> IpSet {
  let sorted = ranges.copy()
  sorted.sort_by(fn(a, b) {
    let order = a.lo.compare(b.lo)
    if order == 0 {
      a.hi.compare(b.hi)
    } else {
      order
    }
  })
  let normalized = []
  for item in sorted {
    append_canonical(normalized, item)
  }
  { ranges: normalized, }
}

///|
/// Return a copy of the canonical intervals. Modifying the returned array does
/// not mutate this set.
pub fn IpSet::intervals(self : IpSet) -> Array[Interval] {
  self.ranges.copy()
}

///|
/// Whether the set contains no addresses.
pub fn IpSet::is_empty(self : IpSet) -> Bool {
  self.ranges.is_empty()
}

///|
/// Test membership with binary search over normalized intervals.
pub fn IpSet::contains(self : IpSet, address : Address) -> Bool {
  let mut low = 0
  let mut high = self.ranges.length()
  while low < high {
    let middle = low + (high - low) / 2
    let item = self.ranges[middle]
    if address < item.lo {
      high = middle
    } else if address > item.hi {
      low = middle + 1
    } else {
      return address.family() == item.lo.family()
    }
  }
  false
}

///|
/// Return all addresses present in either operand. Neither operand is mutated.
/// Runs in O(m+n) for m and n canonical intervals.
pub fn IpSet::union(self : IpSet, other : IpSet) -> IpSet {
  let output = []
  let mut i = 0
  let mut j = 0
  while i < self.ranges.length() || j < other.ranges.length() {
    if j >= other.ranges.length() ||
      (i < self.ranges.length() && self.ranges[i].lo <= other.ranges[j].lo) {
      append_canonical(output, self.ranges[i])
      i = i + 1
    } else {
      append_canonical(output, other.ranges[j])
      j = j + 1
    }
  }
  { ranges: output, }
}

///|
/// Return addresses present in both operands, in O(m+n) interval comparisons.
pub fn IpSet::intersection(self : IpSet, other : IpSet) -> IpSet {
  let output = []
  let mut i = 0
  let mut j = 0
  while i < self.ranges.length() && j < other.ranges.length() {
    let a = self.ranges[i]
    let b = other.ranges[j]
    if a.lo.family() != b.lo.family() {
      if a.lo < b.lo {
        i = i + 1
      } else {
        j = j + 1
      }
      continue
    }
    let lo = if a.lo > b.lo { a.lo } else { b.lo }
    let hi = if a.hi < b.hi { a.hi } else { b.hi }
    if lo <= hi {
      append_canonical(output, { lo, hi, })
    }
    if a.hi < b.hi {
      i = i + 1
    } else if b.hi < a.hi {
      j = j + 1
    } else {
      i = i + 1
      j = j + 1
    }
  }
  { ranges: output, }
}

///|
/// Return addresses in this set but not in `other`.
/// Closed intervals avoid an unrepresentable 2^128 upper endpoint. Optional
/// successor/predecessor values handle the two domain limits explicitly.
pub fn IpSet::difference(self : IpSet, other : IpSet) -> IpSet {
  let output = []
  let mut j = 0
  for source in self.ranges {
    while j < other.ranges.length() && other.ranges[j].hi < source.lo {
      j = j + 1
    }
    let mut cursor = Some(source.lo)
    while j < other.ranges.length() {
      let exclusion = other.ranges[j]
      if exclusion.lo > source.hi || exclusion.lo.family() != source.lo.family() {
        break
      }
      match cursor {
        None => break
        Some(first) => {
          if exclusion.lo > first {
            // exclusion.lo > first ensures a predecessor exists in this family.
            match exclusion.lo.previous() {
              Some(last) => append_canonical(output, { lo: first, hi: last, })
              None => ()
            }
          }
          if exclusion.hi >= source.hi {
            cursor = None
            // Keep this exclusion: it may also cover a later source interval.
            break
          }
          // exclusion.hi < source.hi ensures a successor exists.
          cursor = exclusion.hi.next()
          j = j + 1
        }
      }
    }
    match cursor {
      Some(first) => append_canonical(output, { lo: first, hi: source.hi, })
      None => ()
    }
  }
  { ranges: output, }
}

///|
/// Return addresses present in exactly one operand.
pub fn IpSet::symmetric_difference(self : IpSet, other : IpSet) -> IpSet {
  self.difference(other).union(other.difference(self))
}

///|
/// Whether every address in this set also belongs to `other`.
pub fn IpSet::is_subset_of(self : IpSet, other : IpSet) -> Bool {
  self.difference(other).is_empty()
}

///|
/// Whether the operands share at least one address.
pub fn IpSet::overlaps(self : IpSet, other : IpSet) -> Bool {
  let mut i = 0
  let mut j = 0
  while i < self.ranges.length() && j < other.ranges.length() {
    let a = self.ranges[i]
    let b = other.ranges[j]
    if a.lo.family() == b.lo.family() && a.lo <= b.hi && b.lo <= a.hi {
      return true
    }
    if a.hi < b.hi {
      i = i + 1
    } else {
      j = j + 1
    }
  }
  false
}

///|
/// Return the sorted minimal CIDR cover of this set, without enumerating hosts.
/// At each cursor take the largest aligned block contained in its interval.
/// A /0 is emitted directly for a full address family.
pub fn IpSet::cidrs(self : IpSet) -> Array[Cidr] {
  let output = []
  for item in self.ranges {
    let mut cursor = item.lo
    while true {
      let mut prefix = cursor.width() - cursor.trailing_zeros()
      let mut last = cursor.block_end(prefix)
      while last > item.hi {
        prefix = prefix + 1
        last = cursor.block_end(prefix)
      }
      output.push(cidr_from_normalized(cursor, prefix))
      if last == item.hi {
        break
      }
      match last.next() {
        Some(next) => cursor = next
        None => break
      }
    }
  }
  output
}
