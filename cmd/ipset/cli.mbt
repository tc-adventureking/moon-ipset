///|
enum CliMode {
  Jsonl
  Normalize(String)
  Diff(String, String)
  Help
}

///|
struct CliOptions {
  mode : CliMode
  strict : Bool
  json : Bool
}

///|
struct CliResult {
  stdout : String
  stderr : String
  status : Int32
}

///|
fn usage() -> String {
  let text =
    #|Usage: ipset [jsonl]
    #|       ipset normalize [--strict] [--json] [--] FILE
    #|       ipset diff [--strict] [--json] [--] OLD NEW
    #|       ipset --help
    #|
    #|FILE is a UTF-8 list with one IP or CIDR per line; '-' reads stdin once.
    #|Blank lines, surrounding whitespace, and # comments are ignored.
    #|CRLF and an initial UTF-8 BOM are supported. Bare IPs mean /32 or /128.
    #|--strict rejects CIDRs with host bits set; the default masks host bits.
    #|--json emits {cidrs:[...]} for normalize or {added:[...],removed:[...]} for diff.
    #|-- ends options, allowing filenames that begin with '-'.
    #|Without arguments (or with jsonl), read JSON requests from stdin, one per line.
    #|Exit codes: 0 success/no changes, 1 diff has changes, 2 input/usage error.
    #|
  text
}

///|
fn parse_arguments(arguments : Array[String]) -> CliOptions raise RequestError {
  // Help is available before `--`, independently of the remaining arguments.
  for argument in arguments {
    if argument == "--" {
      break
    }
    if argument == "--help" || argument == "-h" {
      return { mode: Help, strict: false, json: false, }
    }
  }
  let positional : Array[String] = []
  let mut options = true
  let mut strict = false
  let mut json = false
  for argument in arguments {
    if options && argument == "--" {
      options = false
    } else if options && argument == "--strict" {
      strict = true
    } else if options && argument == "--json" {
      json = true
    } else if options && argument != "-" && argument.has_prefix("-") {
      raise InvalidRequest("unknown option: \{argument}; use --help")
    } else {
      positional.push(argument)
    }
  }
  let mode = match positional[:] {
    [] | ["jsonl"] => {
      if strict || json {
        raise InvalidRequest("--strict and --json require normalize or diff")
      }
      Jsonl
    }
    ["normalize", file] => Normalize(file)
    ["diff", old, new] => {
      if old == "-" && new == "-" {
        raise InvalidRequest("stdin '-' may be used only once")
      }
      Diff(old, new)
    }
    _ =>
      raise InvalidRequest(
        "expected jsonl, normalize FILE, or diff OLD NEW; use --help",
      )
  }
  { mode, strict, json, }
}

///|
fn parse_manifest(
  content : String,
  filename : String,
  strict : Bool,
) -> @net.IpSet raise RequestError {
  let content = match content.strip_prefix("\u{FEFF}") {
    Some(rest) => rest.to_owned()
    None => content
  }
  let ranges : Array[@net.Interval] = []
  let mut line_number = 0
  for line in content.split("\n") {
    line_number += 1
    let text = match line.split_once("#") {
      Some((before, _)) => before.trim().to_owned()
      None => line.trim().to_owned()
    }
    if text.is_empty() {
      continue
    }
    let range = try {
      if text.contains("/") {
        let cidr = @net.Cidr::parse(text, strict~)
        @net.Interval::new(cidr.network(), cidr.last())
      } else {
        let address = @net.Address::parse(text)
        @net.Interval::new(address, address)
      }
    } catch {
      error => raise InvalidRequest("\{filename}:\{line_number}: \{error}")
    }
    ranges.push(range)
  }
  @net.IpSet::from_ranges(ranges)
}

///|
fn cidr_strings(set : @net.IpSet) -> Array[String] {
  set.cidrs().map(cidr => cidr.to_string())
}

///|
fn json_strings(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}

///|
fn output_lines(lines : Array[String]) -> String {
  if lines.is_empty() {
    ""
  } else {
    lines.join("\n") + "\n"
  }
}

///|
fn execute_cli(
  options : CliOptions,
  reader : (String) -> String raise,
) -> CliResult raise {
  match options.mode {
    Help => { stdout: usage(), stderr: "", status: 0, }
    Jsonl => {
      let lines : Array[String] = []
      for line in reader("-").split("\n") {
        if !line.trim().is_empty() {
          lines.push(handle_line(line.to_owned()).stringify())
        }
      }
      { stdout: output_lines(lines), stderr: "", status: 0, }
    }
    Normalize(file) => {
      let values = cidr_strings(
        parse_manifest(reader(file), file, options.strict),
      )
      let stdout = if options.json {
        Json::object({ "cidrs": json_strings(values) }).stringify() + "\n"
      } else {
        output_lines(values)
      }
      { stdout, stderr: "", status: 0, }
    }
    Diff(old_file, new_file) => {
      let old = parse_manifest(reader(old_file), old_file, options.strict)
      let new = parse_manifest(reader(new_file), new_file, options.strict)
      let added = cidr_strings(new.difference(old))
      let removed = cidr_strings(old.difference(new))
      let stdout = if options.json {
        Json::object({
          "added": json_strings(added),
          "removed": json_strings(removed),
        }).stringify() +
        "\n"
      } else {
        "Added:\n" + output_lines(added) + "Removed:\n" + output_lines(removed)
      }
      let status = if added.is_empty() && removed.is_empty() { 0 } else { 1 }
      { stdout, stderr: "", status, }
    }
  }
}

///|
fn run_cli(
  arguments : Array[String],
  reader : (String) -> String raise,
) -> CliResult {
  execute_cli(parse_arguments(arguments), reader) catch {
    InvalidRequest(message) =>
      { stdout: "", stderr: message + "\n", status: 2, }
    error => { stdout: "", stderr: "\{error}\n", status: 2, }
  }
}

///|
extern "js" fn host_arguments() -> String =
  #| () => JSON.stringify({args: process.argv.slice(2)})

///|
extern "js" fn host_read_file(filename : String) -> String =
  #| (filename) => {
  #|   try {
  #|     const bytes = process.getBuiltinModule("fs").readFileSync(filename === "-" ? 0 : filename);
  #|     const decoder = new TextDecoder("utf-8", {fatal: true, ignoreBOM: true});
  #|     try {
  #|       return JSON.stringify({ok: true, text: decoder.decode(bytes)});
  #|     } catch {
  #|       // Find the first physical line only on the uncommon decoding-error path.
  #|       for (let start = 0, line = 1; start <= bytes.length; line++) {
  #|         const newline = bytes.indexOf(10, start);
  #|         const end = newline < 0 ? bytes.length : newline;
  #|         try { decoder.decode(bytes.subarray(start, end)); }
  #|         catch { return JSON.stringify({ok: false, line: String(line), error: "invalid UTF-8"}); }
  #|         if (end === bytes.length) break;
  #|         start = end + 1;
  #|       }
  #|       return JSON.stringify({ok: false, error: "invalid UTF-8"});
  #|     }
  #|   } catch (error) {
  #|     return JSON.stringify({ok: false, error: error instanceof Error ? error.message : String(error)});
  #|   }
  #| }

///|
fn read_text(filename : String) -> String raise {
  let response = @json.parse(host_read_file(filename))
  match field_value(response, "ok") {
    Some(True) => required_string(response, "text")
    _ => {
      let message = required_string(response, "error")
      match field_value(response, "line") {
        Some(String(line)) =>
          raise InvalidRequest("\{filename}:\{line}: \{message}")
        _ => raise InvalidRequest("\{filename}: \{message}")
      }
    }
  }
}

///|
extern "js" fn host_stdout(text : String) -> Unit =
  #| (text) => { if (text.length) process.stdout.write(text); }

///|
extern "js" fn host_stderr(text : String) -> Unit =
  #| (text) => { if (text.length) process.stderr.write(text); }

///|
extern "js" fn host_status(status : Int32) -> Unit =
  #| (status) => { process.exitCode = status; }
