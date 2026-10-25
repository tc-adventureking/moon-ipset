///|
suberror RequestError {
  InvalidRequest(String)
}

///|
fn field_value(request : Json, field : String) -> Json? {
  match request {
    Object(fields) => fields.get(field)
    _ => None
  }
}

///|
fn required_string(request : Json, field : String) -> String raise RequestError {
  match field_value(request, field) {
    Some(String(text)) => text
    Some(_) => raise InvalidRequest("\{field} must be a string")
    None => raise InvalidRequest("missing field: \{field}")
  }
}

///|
fn required_strings(
  request : Json,
  field : String,
) -> Array[String] raise RequestError {
  let items = match field_value(request, field) {
    Some(Array(items)) => items
    Some(_) => raise InvalidRequest("\{field} must be an array of strings")
    None => raise InvalidRequest("missing field: \{field}")
  }
  let result : Array[String] = []
  for item in items {
    match item {
      String(text) => result.push(text)
      _ => raise InvalidRequest("\{field} must contain only strings")
    }
  }
  result
}

///|
fn cidr_result(set : @net.IpSet) -> Json {
  Json::object({
    "ok": Json::boolean(true),
    "cidrs": Json::array(
      set.cidrs().map(cidr => Json::string(cidr.to_string())),
    ),
  })
}

///|
fn evaluate(request : Json) -> Json raise {
  match request {
    Object(_) => ()
    _ => raise InvalidRequest("request must be a JSON object")
  }
  let operation = required_string(request, "op")
  match operation {
    "parse" => {
      let address = @net.Address::parse(required_string(request, "address"))
      Json::object({
        "ok": Json::boolean(true),
        "address": Json::string(address.to_string()),
        "family": Json::number(
          if address.family() == @net.V4 {
            4.0
          } else {
            6.0
          },
        ),
      })
    }
    "network" => {
      let strict = match field_value(request, "strict") {
        None => false
        Some(True) => true
        Some(False) => false
        Some(_) => raise InvalidRequest("strict must be a boolean")
      }
      let cidr = @net.Cidr::parse(required_string(request, "cidr"), strict~)
      Json::object({
        "ok": Json::boolean(true),
        "cidr": Json::string(cidr.to_string()),
      })
    }
    "normalize" =>
      cidr_result(@net.IpSet::from_cidrs(required_strings(request, "cidrs")))
    "union" | "intersection" | "difference" | "symmetric_difference" => {
      let left = @net.IpSet::from_cidrs(required_strings(request, "left"))
      let right = @net.IpSet::from_cidrs(required_strings(request, "right"))
      let result = match operation {
        "union" => left.union(right)
        "intersection" => left.intersection(right)
        "difference" => left.difference(right)
        _ => left.symmetric_difference(right)
      }
      cidr_result(result)
    }
    "range" => {
      let start = @net.Address::parse(required_string(request, "start"))
      let end = @net.Address::parse(required_string(request, "end"))
      cidr_result(@net.IpSet::from_ranges([@net.Interval::new(start, end)]))
    }
    "contains" => {
      let set = @net.IpSet::from_cidrs(required_strings(request, "cidrs"))
      let address = @net.Address::parse(required_string(request, "address"))
      Json::object({
        "ok": Json::boolean(true),
        "value": Json::boolean(set.contains(address)),
      })
    }
    _ => raise InvalidRequest("unknown operation: \{operation}")
  }
}

///|
fn handle_line(text : String) -> Json {
  evaluate(@json.parse(text, reject_duplicate_keys=true)) catch {
    error =>
      Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(error.to_string()),
      })
  }
}

///|
fn main {
  let result = run_cli(
    required_strings(@json.parse(host_arguments()), "args"),
    read_text,
  ) catch {
    error => { stdout: "", stderr: "\{error}\n", status: 2, }
  }
  host_stdout(result.stdout)
  host_stderr(result.stderr)
  host_status(result.status)
}
