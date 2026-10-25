///|
test "JSON parse and strict network" {
  assert_eq(
    handle_line("{\"op\":\"parse\",\"address\":\"2001:DB8::1\"}"),
    @json.parse("{\"ok\":true,\"address\":\"2001:db8::1\",\"family\":6}"),
  )
  assert_eq(
    field_value(
      handle_line(
        "{\"op\":\"network\",\"cidr\":\"10.0.0.1/24\",\"strict\":true}",
      ),
      "ok",
    ),
    Some(Json::boolean(false)),
  )
}

///|
test "JSON malformed or typed request produces an error" {
  for
    text in [
      "{", "null", "[]", "{}", "{\"op\":4}", "{\"op\":\"normalize\",\"cidrs\":[1]}",
      "{\"op\":\"network\",\"cidr\":\"::/0\",\"strict\":1}", "{\"op\":\"parse\",\"op\":\"contains\",\"address\":\"::\"}",
    ] {
    let response = handle_line(text)
    assert_eq(field_value(response, "ok"), Some(Json::boolean(false)))
    assert_true(field_value(response, "error") is Some(_))
  }
}

///|
test "JSON difference is a complete response" {
  assert_eq(
    handle_line(
      "{\"op\":\"difference\",\"left\":[\"10.0.0.0/24\"],\"right\":[\"10.0.0.0/25\"]}",
    ),
    @json.parse("{\"ok\":true,\"cidrs\":[\"10.0.0.128/25\"]}"),
  )
}
