///|
fn response(request : Json) -> Json raise {
  Json::object({ "ok": jb(true), "value": evaluate(request) }) catch {
    @net.InvalidAddress(_)
    | @net.InvalidPrefix(_)
    | @net.InvalidRange(_)
    | @net.HostBitsSet(_) => Json::object({ "ok": jb(false) })
    error => raise error
  }
}

///|
fn run_vectors(vectors : String, adapted : Bool) -> Int32 raise {
  let mut count = 0
  for line in vectors.split("\n") {
    let row = @json.parse(line.to_owned())
    let category = text(row, "category")
    let request = field(row, "request").unwrap()
    let expected = field(row, "expected").unwrap()
    if adapted {
      assert_true(
        field(row, "cpython_result").unwrap() != expected,
        msg=category,
      )
    }
    let actual = response(request) catch {
      error => {
        assert_true(
          false,
          msg="adapter failed: \{category}: \{request.stringify()}: \{error}",
        )
        Json::null()
      }
    }
    assert_eq(actual, expected, msg="\{category}: \{request.stringify()}")
    count += 1
  }
  count
}

///|
test "pinned CPython strict vectors" {
  assert_eq(run_vectors(strict_vectors, false), 1119)
}

///|
test "declared adaptations remain separate from strict comparisons" {
  assert_eq(run_vectors(adapted_vectors, true), 44)
}

///|
test "adapter mistakes are not successful input rejection" {
  let requests : Array[Json] = [
    { "op": "not_an_operation" },
    { "op": "address_bytes", "bytes": [256, 0, 0, 0] },
  ]
  for request in requests {
    let invalid = try {
      ignore(response(request))
      false
    } catch {
      Invalid => true
      _ => false
    }
    assert_true(invalid)
  }
  let mut count = 0
  for line in protocol_rejections.split("\n") {
    let request = @json.parse(line.to_owned())
    let invalid = try {
      ignore(response(request))
      false
    } catch {
      Invalid => true
      _ => false
    }
    assert_true(invalid, msg=request.stringify())
    count += 1
  }
  assert_eq(count, 10)
}
