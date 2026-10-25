///|
test "manifest accepts BOM CRLF comments and bare addresses" {
  let result = run_cli(["normalize", "list.txt"], _ => {
    "\u{FEFF} # heading\r\n 192.0.2.1 # host\r\n192.0.2.0\r\n::1\r\n::1/128\r\n\r\n"
  })
  assert_eq(result.status, 0)
  assert_eq(result.stderr, "")
  assert_eq(result.stdout, "192.0.2.0/31\n::1/128\n")
  let empty = run_cli(["normalize", "--json", "empty"], _ => "# nothing\n")
  assert_eq(empty.status, 0)
  assert_eq(@json.parse(empty.stdout), @json.parse("{\"cidrs\":[]}"))
}

///|
test "manifest errors have filename physical line and atomic stdout" {
  let invalid = run_cli(["normalize", "bad.txt"], _ => {
    "# line 1\n192.0.2.0/24\n\n300.0.0.1\n"
  })
  assert_eq(invalid.status, 2)
  assert_eq(invalid.stdout, "")
  assert_true(invalid.stderr.has_prefix("bad.txt:4: "))
  let strict = run_cli(["normalize", "host.txt", "--strict"], _ => {
    "\n10.0.0.1/24\n"
  })
  assert_eq(strict.status, 2)
  assert_eq(strict.stdout, "")
  assert_true(strict.stderr.has_prefix("host.txt:2: "))
  let relaxed = run_cli(["normalize", "host.txt"], _ => "10.0.0.1/24\n")
  assert_eq(relaxed.status, 0)
  assert_eq(relaxed.stdout, "10.0.0.0/24\n")
}

///|
test "strict and default reject ambiguous address forms" {
  for invalid in ["01.2.3.4", "fe80::1%eth0", "10.0.0.1 10.0.0.2"] {
    for
      arguments in [["normalize", "input"], ["normalize", "--strict", "input"]] {
      let result = run_cli(arguments, _ => invalid)
      assert_eq(result.status, 2)
      assert_eq(result.stdout, "")
      assert_true(result.stderr.has_prefix("input:1: "))
    }
  }
}

///|
test "diff uses new minus old and old minus new" {
  let reader : (String) -> String raise = fn(filename) {
    if filename == "old" {
      "10.0.0.0/24\n2001:db8::/126\n"
    } else {
      "10.0.0.128/25\n192.0.2.1\n2001:db8::/127\n"
    }
  }
  let result = run_cli(["diff", "old", "new"], reader)
  assert_eq(result.status, 1)
  assert_eq(result.stderr, "")
  assert_eq(
    result.stdout,
    "Added:\n192.0.2.1/32\nRemoved:\n10.0.0.0/25\n2001:db8::2/127\n",
  )
  let json = run_cli(["--json", "diff", "old", "new"], reader)
  assert_eq(json.status, 1)
  assert_eq(
    @json.parse(json.stdout),
    @json.parse(
      "{\"added\":[\"192.0.2.1/32\"],\"removed\":[\"10.0.0.0/25\",\"2001:db8::2/127\"]}",
    ),
  )
}

///|
test "diff ignores duplicate ordering splitting and host bits by default" {
  let result = run_cli(["diff", "old", "new"], filename => {
    if filename == "old" {
      "10.0.0.8/24\n::1\n10.0.0.0/24\n"
    } else {
      "::1/128\n10.0.0.128/25\n10.0.0.0/25\n"
    }
  })
  assert_eq(result.status, 0)
  assert_eq(result.stdout, "Added:\nRemoved:\n")
  assert_eq(result.stderr, "")
}

///|
test "invalid arguments do not consume input" {
  for
    arguments in [
      ["diff", "-", "-"],
      ["diff", "old"],
      ["normalize"],
      ["normalize", "file", "extra"],
      ["normalize", "--unknown", "file"],
      ["jsonl", "--json"],
      ["--strict"],
      ["unknown"],
    ] {
    let mut reads = 0
    let result = run_cli(arguments, _ => {
      reads += 1
      ""
    })
    assert_eq(result.status, 2)
    assert_eq(result.stdout, "")
    assert_true(!result.stderr.is_empty())
    assert_eq(reads, 0)
  }
}

///|
test "option terminator and help have distinct behavior" {
  let filename = run_cli(["normalize", "--", "--help"], file => {
    assert_eq(file, "--help")
    "::1"
  })
  assert_eq(filename.status, 0)
  assert_eq(filename.stdout, "::1/128\n")
  let mut reads = 0
  let help = run_cli(["diff", "--help"], _ => {
    reads += 1
    ""
  })
  assert_eq(help.status, 0)
  assert_true(help.stdout.has_prefix("Usage: ipset"))
  assert_eq(reads, 0)
}

///|
test "later input errors produce no partial diff" {
  let invalid = run_cli(["diff", "old", "new"], file => {
    if file == "old" {
      "10.0.0.0/24"
    } else {
      "::1\ninvalid"
    }
  })
  assert_eq(invalid.status, 2)
  assert_eq(invalid.stdout, "")
  assert_true(invalid.stderr.has_prefix("new:2: "))
  let missing = run_cli(["diff", "old", "missing"], file => {
    if file == "missing" {
      raise InvalidRequest("missing: cannot read file")
    }
    "10.0.0.0/24"
  })
  assert_eq(missing.status, 2)
  assert_eq(missing.stdout, "")
  assert_eq(missing.stderr, "missing: cannot read file\n")
}

///|
test "JSONL remains available as default and explicit command" {
  let input = "\n{\"op\":\"parse\",\"address\":\"::1\"}\n{\n"
  let default = run_cli([], _ => input)
  let explicit = run_cli(["jsonl"], _ => input)
  assert_eq(default.status, 0)
  assert_eq(default.stdout, explicit.stdout)
  assert_eq(default.stderr, "")
  let lines = default.stdout.split("\n").to_array()
  assert_eq(lines.length(), 3)
  assert_eq(
    field_value(@json.parse(lines[0].to_owned()), "ok"),
    Some(Json::boolean(true)),
  )
  assert_eq(
    field_value(@json.parse(lines[1].to_owned()), "ok"),
    Some(Json::boolean(false)),
  )
}

///|
test "JSONL strips one BOM only at the start of input" {
  let valid = "{\"op\":\"parse\",\"address\":\"::1\"}"
  for arguments in [[], ["jsonl"]] {
    let result = run_cli(arguments, _ => {
      "\u{FEFF}" + valid + "\r\n\u{FEFF}" + valid + "\n" + valid
    })
    assert_eq(result.status, 0)
    assert_eq(result.stderr, "")
    let lines = result.stdout.split("\n").to_array()
    assert_eq(lines.length(), 4)
    for i in 0..<3 {
      assert_eq(
        field_value(@json.parse(lines[i].to_owned()), "ok"),
        Some(Json::boolean(i != 1)),
      )
    }
  }
  let repeated = run_cli([], _ => "\u{FEFF}\u{FEFF}" + valid)
  assert_eq(
    field_value(@json.parse(repeated.stdout), "ok"),
    Some(Json::boolean(false)),
  )
  let after_blank = run_cli([], _ => "\n\u{FEFF}" + valid)
  assert_eq(
    field_value(@json.parse(after_blank.stdout), "ok"),
    Some(Json::boolean(false)),
  )
}
