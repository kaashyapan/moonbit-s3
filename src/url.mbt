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
    VirtualHost => @sigv4.percent_encode(object, slash_okay=true)
    Path => {
      let encoded_bucket = @sigv4.percent_encode(bucket)
      let encoded_object = @sigv4.percent_encode(object, slash_okay=true)
      "/\{encoded_bucket}\{encoded_object}"
    }
  }
}

///|
fn append_query(path : String, query : Map[String, String]) -> String {
  if query.is_empty() {
    path
  } else {
    "\{path}?\{@sigv4.canonical_query(query)}"
  }
}
