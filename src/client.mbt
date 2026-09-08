///|
fn Client::prepare_request(
  self : Client,
  meth : S3Method,
  bucket : String,
  key : String,
  body : &@io.Data,
  options? : RequestOptions = RequestOptions(),
) -> Request raise {
  if bucket == "" {
    raise S3Error::InvalidInput("bucket must not be empty")
  }
  let timestamp = match options.timestamp {
    Some(value) => value
    None => now_timestamp()
  }
  let payload_hash = match options.payload_hash {
    Some(value) => value
    None => sha256_data_hex(body)
  }
  let (origin, host) = endpoint_origin_and_host(self.config, bucket)
  let path = canonical_object_path(self.config, bucket, key)
  let headers = copy_user_headers(options.headers)
  if meth is Put && !contains_header(headers, "content-length") {
    headers["Content-Length"] = body.binary().length().to_string()
  }
  headers["Accept-Encoding"] = "identity"
  headers["Host"] = host
  headers["x-amz-date"] = timestamp
  headers["x-amz-content-sha256"] = payload_hash
  if self.config.credentials.session_token is Some(token) {
    headers["x-amz-security-token"] = token
  }
  let headers = @sigv4.sign_headers(
    method_name(meth),
    path,
    options.query,
    headers,
    payload_hash,
    to_sigv4_credentials(self.config.credentials),
    self.config.region,
    "s3",
    timestamp,
  )
  { origin, target: append_query(path, options.query), headers, }
}

///|
fn ensure_object_key(key : String) -> Unit raise {
  if key == "" {
    raise S3Error::InvalidInput("key must not be empty")
  }
}

///|
fn copy_user_headers(headers : Map[String, String]) -> Map[String, String] {
  let copied : Map[String, String] = Map([])
  for key, value in headers {
    if !is_signer_controlled_header(key) {
      copied[key] = value
    }
  }
  copied
}

///|
fn is_signer_controlled_header(name : String) -> Bool {
  name.compare_ignore_ascii_case("accept-encoding") == 0 ||
  name.compare_ignore_ascii_case("authorization") == 0 ||
  name.compare_ignore_ascii_case("host") == 0 ||
  name.compare_ignore_ascii_case("transfer-encoding") == 0 ||
  name.compare_ignore_ascii_case("x-amz-content-sha256") == 0 ||
  name.compare_ignore_ascii_case("x-amz-date") == 0 ||
  name.compare_ignore_ascii_case("x-amz-security-token") == 0
}

///|
fn contains_header(headers : Map[String, String], name : String) -> Bool {
  for key, _ in headers {
    if key.compare_ignore_ascii_case(name) == 0 {
      return true
    }
  }
  false
}

///|
fn http_method(meth : S3Method) -> @http.RequestMethod {
  match meth {
    Get => @http.Get
    Head => @http.Head
    Put => @http.Put
    Delete => @http.Delete
  }
}

///|
async fn[T] Client::send(
  self : Client,
  meth : S3Method,
  bucket : String,
  key : String,
  body : &@io.Data,
  options? : RequestOptions = RequestOptions(),
  f : async (@http.Response, @http.Client) -> T,
) -> T {
  let request = self.prepare_request(meth, bucket, key, body, options~)
  let client = @http.Client(request.origin)
  let extra_headers = Map([])
  request
  .extra_headers()
  .each((key, val) => extra_headers.set(@http.CaseInsensitiveString(key), val))

  defer client.close()
  client.request(http_method(meth), request.target, extra_headers~)
  if meth is Put {
    client.write(body)
  }
  let response = client.end_request()
  f(response, client)
}

///|
fn Request::extra_headers(self : Request) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  for key, value in self.headers {
    if key.compare_ignore_ascii_case("host") != 0 {
      headers[key] = value
    }
  }
  headers
}

///|
fn ensure_success_response(
  response : @http.Response,
  body : String,
) -> Unit raise {
  if !is_success_response(response) {
    raise S3Error::ServiceError(response, body)
  }
}

///|
fn is_success_response(response : @http.Response) -> Bool {
  response.code >= 200 && response.code < 300
}

///|
async fn read_error_body(client : @http.Client) -> String {
  client.read_all().text()
}

///|
async fn raise_service_error_response(
  response : @http.Response,
  client : @http.Client,
) -> Unit {
  let body = read_error_body(client)
  raise S3Error::ServiceError(response, body)
}

///|
fn raise_service_error_response_without_body(
  response : @http.Response,
) -> Unit raise {
  raise S3Error::ServiceError(response, "")
}

///|
pub async fn Client::get_object(
  self : Client,
  bucket : String,
  key : String,
  options? : RequestOptions = RequestOptions(),
) -> ObjectResult {
  ensure_object_key(key)
  let request = self.prepare_request(Get, bucket, key, b"", options~)
  let client = @http.Client(request.origin)
  let extra_headers = Map([])
  request
  .extra_headers()
  .each((key, val) => extra_headers.set(@http.CaseInsensitiveString(key), val))

  errdefer client.close()
  let response = client
    ..request(@http.Get, request.target, extra_headers~)
    .end_request()
  if !is_success_response(response) {
    defer client.close()
    raise_service_error_response(response, client)
  }
  { response, body: client, }
}

///|
pub async fn Client::put_object(
  self : Client,
  bucket : String,
  key : String,
  body : &@io.Data,
  options? : RequestOptions = RequestOptions(),
) -> @http.Response {
  ensure_object_key(key)
  self.send(Put, bucket, key, body, options~, (response, client) => {
    if !is_success_response(response) {
      raise_service_error_response(response, client)
    }
    response
  })
}

///|
pub async fn Client::delete_object(
  self : Client,
  bucket : String,
  key : String,
  options? : RequestOptions = RequestOptions(),
) -> @http.Response {
  ensure_object_key(key)
  self.send(Delete, bucket, key, b"", options~, (response, client) => {
    if !is_success_response(response) {
      raise_service_error_response(response, client)
    }
    response
  })
}

///|
pub async fn Client::head_object(
  self : Client,
  bucket : String,
  key : String,
  options? : RequestOptions = RequestOptions(),
) -> @http.Response {
  ensure_object_key(key)
  self.send(Head, bucket, key, b"", options~, (response, client) => {
    if !is_success_response(response) {
      ignore(client)
      raise_service_error_response_without_body(response)
    }
    response
  })
}

///|
pub async fn Client::list_objects_v2(
  self : Client,
  bucket : String,
  prefix? : String,
  delimiter? : String,
  continuation_token? : String,
  max_keys? : Int,
  options? : RequestOptions = RequestOptions(),
) -> ListObjectsV2Result {
  let query = options.query.copy()
  query["list-type"] = "2"
  if prefix is Some(value) {
    query["prefix"] = value
  }
  if delimiter is Some(value) {
    query["delimiter"] = value
  }
  if continuation_token is Some(value) {
    query["continuation-token"] = value
  }
  if max_keys is Some(value) {
    query["max-keys"] = value.to_string()
  }
  let options = {
    headers: options.headers,
    query,
    timestamp: options.timestamp,
    payload_hash: options.payload_hash,
  }
  self.send(Get, bucket, "", b"", options~, (response, client) => {
    let body = client.read_all().text()
    ensure_success_response(response, body)
    parse_list_objects_v2(body)
  })
}

///|
fn Client::presigned_url(
  self : Client,
  meth : S3Method,
  bucket : String,
  key : String,
  expires_seconds? : Int = 3600,
  content_type? : String,
) -> String raise {
  ensure_object_key(key)
  if expires_seconds <= 0 || expires_seconds > 604800 {
    raise S3Error::InvalidInput("expires_seconds must be between 1 and 604800")
  }
  let (origin, host) = endpoint_origin_and_host(self.config, bucket)
  let path = canonical_object_path(self.config, bucket, key)
  let signed_headers : Map[String, String] = Map([])
  if content_type is Some(value) {
    signed_headers["content-type"] = value
  }
  let query = @sigv4.presign_query(
    method_name(meth),
    path,
    host,
    to_sigv4_credentials(self.config.credentials),
    self.config.region,
    "s3",
    now_timestamp(),
    expires_seconds,
    signed_headers~,
  )
  "\{origin}\{append_query(path, query)}"
}

///|
/// Generate a presigned GET URL for an S3 object.
///
///    :param bucket: Name of the S3 bucket
///    :param key: Key (path) of the object within the bucket
///    :param expires_seconds: Time in seconds for the URL to remain valid
///        (default 1 hour, maximum 7 days)
///    :return: Presigned URL as a string
pub fn Client::generate_presigned_get_url(
  self : Client,
  bucket : String,
  key : String,
  expires_seconds? : Int = 3600,
) -> String raise {
  self.presigned_url(Get, bucket, key, expires_seconds~)
}

///|
/// Generate a presigned PUT URL for uploading an object directly to S3.
///
///    :param bucket: Name of the S3 bucket
///    :param key: Key (path) where the object will be stored
///    :param expires_seconds: Time in seconds the URL remains valid
///        (default 1 hour, maximum 7 days)
///    :param content_type: Optional — if set, the client MUST send this exact
///        Content-Type header when uploading, or S3 will reject it
///    :return: Presigned URL as a string
pub fn Client::generate_presigned_put_url(
  self : Client,
  bucket : String,
  key : String,
  expires_seconds? : Int = 3600,
  content_type? : String,
) -> String raise {
  self.presigned_url(Put, bucket, key, expires_seconds~, content_type?)
}

///|
impl ReadCloser for @http.Client

///|
impl ReadCloser for @http.Client with fn close(self) {
  self.close()
}
