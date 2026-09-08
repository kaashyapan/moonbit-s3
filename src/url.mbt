///|
fn is_unreserved_byte(byte : Byte) -> Bool {
  let n = byte.to_int()
  (n >= 65 && n <= 90) ||
  (n >= 97 && n <= 122) ||
  (n >= 48 && n <= 57) ||
  byte is b'-' ||
  byte is b'_' ||
  byte is b'.' ||
  byte is b'~'
}

///|
fn hex_digit(n : Int) -> Char {
  if n < 10 {
    (n + '0'.to_int()).unsafe_to_char()
  } else {
    (n - 10 + 'A'.to_int()).unsafe_to_char()
  }
}

///|
fn percent_encode(input : StringView, slash_okay? : Bool = false) -> String {
  let out = StringBuilder()
  for ch in input {
    if ch.is_ascii() {
      let byte = ch.to_int().to_byte()
      if is_unreserved_byte(byte) || (slash_okay && byte is b'/') {
        out.write_char(ch)
      } else {
        let n = byte.to_int()
        out.write_char('%')
        out.write_char(hex_digit(n / 16))
        out.write_char(hex_digit(n % 16))
      }
    } else {
      let bytes = @utf8.encode(ch.to_string())
      for byte in bytes {
        let n = byte.to_int()
        out.write_char('%')
        out.write_char(hex_digit(n / 16))
        out.write_char(hex_digit(n % 16))
      }
    }
  }
  out.to_string()
}

///|
fn endpoint_origin_and_host(
  config : Config,
  bucket : String,
) -> (String, String) {
  let endpoint = match config.endpoint {
    Some(value) => value.trim_end(chars="/").to_owned()
    None => "https://s3.\{config.region}.amazonaws.com"
  }
  match config.endpoint_style {
    Path => {
      let (scheme, endpoint_host) = endpoint_parts(endpoint)
      ("\{scheme}://\{endpoint_host}", endpoint_host)
    }
    VirtualHost => {
      let (scheme, endpoint_host) = endpoint_parts(endpoint)
      let origin_host = "\{bucket}.\{endpoint_host}"
      ("\{scheme}://\{origin_host}", origin_host)
    }
  }
}

///|
fn endpoint_parts(endpoint : String) -> (String, String) {
  match endpoint.find("://") {
    Some(i) => (endpoint[:i].to_owned(), endpoint[i + 3:].to_owned())
    None => ("https", endpoint)
  }
}

///|
fn canonical_object_path(
  config : Config,
  bucket : String,
  key : String,
) -> String {
  let object = if key == "" { "/" } else { "/\{key}" }
  match config.endpoint_style {
    VirtualHost => percent_encode(object, slash_okay=true)
    Path =>
      "/\{percent_encode(bucket)}\{percent_encode(object, slash_okay=true)}"
  }
}

///|
fn canonical_query(query : Map[String, String]) -> String {
  let pairs = query.to_array()
  pairs.sort_by(fn(left, right) {
    let lk = percent_encode(left.0)
    let rk = percent_encode(right.0)
    let c = lk.compare(rk)
    if c == 0 {
      percent_encode(left.1).compare(percent_encode(right.1))
    } else {
      c
    }
  })
  pairs
  .map(fn(pair) { "\{percent_encode(pair.0)}=\{percent_encode(pair.1)}" })
  .join("&")
}

///|
fn append_query(path : String, query : Map[String, String]) -> String {
  if query.is_empty() {
    path
  } else {
    "\{path}?\{canonical_query(query)}"
  }
}
