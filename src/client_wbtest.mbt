///|
fn Client::signed_request(
  self : Client,
  meth : S3Method,
  bucket : String,
  key : String,
  body? : &@io.Data = b"",
  options? : RequestOptions = RequestOptions(),
) -> Request raise {
  self.prepare_request(meth, bucket, key, body, options~)
}

///|
fn test_client(
  endpoint : String,
  session_token? : String,
  endpoint_style? : EndpointStyle = Path,
) -> Client raise {
  let credentials = match session_token {
    Some(token) =>
      Credentials(
        "AKIAIOSFODNN7EXAMPLE",
        "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        session_token=token,
      )
    None =>
      Credentials(
        "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
      )
  }
  Client(Config("us-east-1", credentials, endpoint~, endpoint_style~))
}

///|
test "amz timestamp formats UTC basic timestamp" {
  assert_eq(amz_timestamp(0UL), "19700101T000000Z")
  assert_eq(amz_timestamp(1704067200000UL), "20240101T000000Z")
}

///|
test "client constructor raises invalid config" {
  let credentials = Credentials("access", "secret")
  assert_invalid_config(Config("", credentials), "region must not be empty")
  assert_invalid_config(
    Config("us-east-1", Credentials("", "secret")),
    "access key id must not be empty",
  )
  assert_invalid_config(
    Config("us-east-1", Credentials("access", "")),
    "secret access key must not be empty",
  )
}

///|
fn assert_invalid_config(config : Config, message : String) -> Unit raise {
  try {
    ignore(Client(config))
    fail("expected invalid config")
  } catch {
    S3Error::InvalidConfig(actual) => assert_eq(actual, message)
    _ => fail("expected invalid config")
  }
}

///|
test "sha256 empty payload" {
  assert_eq(
    sha256_data_hex(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
}

///|
test "hmac sha256 helper" {
  assert_eq(
    hmac_sha256_hex(b"key", "The quick brown fox jumps over the lazy dog"),
    "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
  )
}

///|
test "signed request uses AWS SigV4 canonical fields" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let req = client.signed_request(
    Get,
    "examplebucket",
    "test.txt",
    options=RequestOptions(timestamp="20130524T000000Z"),
  )
  assert_eq(
    req.headers["Authorization"],
    "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=accept-encoding;host;x-amz-content-sha256;x-amz-date, Signature=1d894ade6e4126ab11faeca99fc31d492718255cfb11a723ed773996ef365e8d",
  )
}

///|
test "parse list objects v2 result" {
  let xml =
    #|<ListBucketResult>
    #|  <IsTruncated>true</IsTruncated>
    #|  <NextContinuationToken>next</NextContinuationToken>
    #|  <Contents><Key>a.txt</Key><ETag>"etag"</ETag><Size>42</Size></Contents>
    #|  <CommonPrefixes><Prefix>dir/</Prefix></CommonPrefixes>
    #|</ListBucketResult>
  let result = parse_list_objects_v2(xml)
  assert_true(result.is_truncated)
  assert_true(result.next_continuation_token is Some("next"))
  assert_eq(result.contents.length(), 1)
  assert_eq(result.contents[0].key, "a.txt")
  assert_eq(result.contents[0].size, 42L)
  assert_eq(result.common_prefixes.length(), 1)
  assert_eq(result.common_prefixes[0], "dir/")
}

///|
test "request extra headers keep signed content length but omit host" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let req = client.signed_request(
    Put,
    "examplebucket",
    "test.txt",
    body=b"hello",
    options=RequestOptions(
      headers={ "Content-Length": "5" },
      timestamp="20130524T000000Z",
    ),
  )
  let extra_headers = req.extra_headers()
  assert_eq(extra_headers["Content-Length"], "5")
  assert_true(extra_headers.get("Host") is None)
  assert_true(extra_headers.get("Authorization") is Some(_))
}

///|
test "put signed request adds content length by default" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let req = client.signed_request(
    Put,
    "examplebucket",
    "test.txt",
    body=b"hello",
    options=RequestOptions(timestamp="20130524T000000Z"),
  )
  assert_eq(req.headers["Content-Length"], "5")
  assert_eq(req.extra_headers()["Content-Length"], "5")
  assert_true(req.headers["Authorization"].contains("content-length"))
}

///|
test "put signed request preserves explicit content length" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let req = client.signed_request(
    Put,
    "examplebucket",
    "test.txt",
    body=b"hello",
    options=RequestOptions(
      headers={ "content-length": "9" },
      timestamp="20130524T000000Z",
    ),
  )
  assert_eq(req.headers["content-length"], "9")
  assert_true(req.headers.get("Content-Length") is None)
}

///|
test "object operations reject empty key before signing" {
  assert_object_key_rejected(Get)
  assert_object_key_rejected(Put)
  assert_object_key_rejected(Head)
  assert_object_key_rejected(Delete)
}

///|
fn assert_object_key_rejected(meth : S3Method) -> Unit raise {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  try {
    ensure_object_key("")
    ignore(
      client.signed_request(
        meth,
        "examplebucket",
        "",
        options=RequestOptions(timestamp="20130524T000000Z"),
      ),
    )
    fail("expected invalid input")
  } catch {
    S3Error::InvalidInput(message) =>
      assert_eq(message, "key must not be empty")
    _ => fail("expected invalid input")
  }
}

///|
test "list request can still use bucket root path" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let req = client.signed_request(
    Get,
    "examplebucket",
    "",
    options=RequestOptions(
      query={ "list-type": "2" },
      timestamp="20130524T000000Z",
    ),
  )
  assert_eq(req.target, "/examplebucket/?list-type=2")
}

///|
test "put signed request keeps content encoding metadata" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let req = client.signed_request(
    Put,
    "examplebucket",
    "test.txt",
    body=b"hello",
    options=RequestOptions(
      headers={ "Content-Encoding": "gzip" },
      timestamp="20130524T000000Z",
    ),
  )
  assert_eq(req.headers["Content-Encoding"], "gzip")
  assert_eq(req.extra_headers()["Content-Encoding"], "gzip")
  assert_true(req.headers["Authorization"].contains("content-encoding"))
}

///|
test "custom port endpoint signs the host sent by http client" {
  let client = test_client("http://127.0.0.1:9000")
  let req = client.signed_request(
    Get,
    "examplebucket",
    "test.txt",
    options=RequestOptions(timestamp="20130524T000000Z"),
  )
  assert_eq(req.headers["Host"], "127.0.0.1:9000")
  assert_true(req.extra_headers().get("Host") is None)
}

///|
test "path style endpoint without scheme defaults origin to https" {
  let client = test_client("s3.example.com")
  let (origin, host) = endpoint_origin_and_host(client.config, "examplebucket")
  assert_eq(origin, "https://s3.example.com")
  assert_eq(host, "s3.example.com")
  let req = client.signed_request(
    Get,
    "examplebucket",
    "test.txt",
    options=RequestOptions(timestamp="20130524T000000Z"),
  )
  assert_eq(req.headers["Host"], "s3.example.com")
}

///|
test "explicit default ports are kept in signed host" {
  let http_client = test_client("http://127.0.0.1:80")
  let https_client = test_client("https://s3.example.com:443")
  let http_req = http_client.signed_request(
    Get,
    "examplebucket",
    "test.txt",
    options=RequestOptions(timestamp="20130524T000000Z"),
  )
  let https_req = https_client.signed_request(
    Get,
    "examplebucket",
    "test.txt",
    options=RequestOptions(timestamp="20130524T000000Z"),
  )
  assert_eq(http_req.headers["Host"], "127.0.0.1:80")
  assert_true(http_req.extra_headers().get("Host") is None)
  assert_eq(https_req.headers["Host"], "s3.example.com:443")
  assert_true(https_req.extra_headers().get("Host") is None)
}

///|
test "presign query follows sigv4 query signing" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let query = presign_query(
    Get,
    "/test.txt",
    "examplebucket.s3.amazonaws.com",
    client.config.credentials,
    "us-east-1",
    "20130524T000000Z",
    86400,
  )
  assert_eq(query["X-Amz-Algorithm"], "AWS4-HMAC-SHA256")
  assert_eq(
    query["X-Amz-Credential"],
    "AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request",
  )
  assert_eq(query["X-Amz-Date"], "20130524T000000Z")
  assert_eq(query["X-Amz-Expires"], "86400")
  assert_eq(
    query["X-Amz-Signature"],
    "3ed0be64024db54d5574a27da223529635c383f911f80e636f0ccc13890053d2",
  )
}

///|
test "presign query signs content type when present" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let query = presign_query(
    Put,
    "/test.txt",
    "examplebucket.s3.amazonaws.com",
    client.config.credentials,
    "us-east-1",
    "20130524T000000Z",
    3600,
    content_type="text/plain",
  )
  assert_eq(query["Content-Type"], "text/plain")
  assert_true(query.get("X-Amz-Signature") is Some(_))
}

///|
test "presign query includes session token" {
  let client = test_client(
    "https://examplebucket.s3.amazonaws.com",
    session_token="session-token",
  )
  let query = presign_query(
    Get,
    "/test.txt",
    "examplebucket.s3.amazonaws.com",
    client.config.credentials,
    "us-east-1",
    "20130524T000000Z",
    3600,
  )
  assert_eq(query["X-Amz-Security-Token"], "session-token")
}

///|
test "generate presigned urls produce signed query strings" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  let get_url = client.generate_presigned_get_url("examplebucket", "test.txt")
  assert_true(
    get_url.has_prefix(
      "https://examplebucket.s3.amazonaws.com/examplebucket/test.txt?",
    ),
  )
  assert_true(get_url.contains("X-Amz-Signature="))
  let put_url = client.generate_presigned_put_url(
    "examplebucket",
    "test.txt",
    content_type="text/plain",
  )
  assert_true(
    put_url.has_prefix(
      "https://examplebucket.s3.amazonaws.com/examplebucket/test.txt?",
    ),
  )
  assert_true(put_url.contains("Content-Type=text%2Fplain"))
}

///|
test "presigned urls reject empty key and invalid expiry" {
  let client = test_client("https://examplebucket.s3.amazonaws.com")
  assert_presigned_url_rejected(
    () => ignore(client.generate_presigned_get_url("examplebucket", "")),
    "key must not be empty",
  )
  assert_presigned_url_rejected(
    () => {
      ignore(
        client.generate_presigned_get_url(
          "examplebucket",
          "a",
          expires_seconds=0,
        ),
      )
    },
    "expires_seconds must be between 1 and 604800",
  )
  assert_presigned_url_rejected(
    () => {
      ignore(
        client.generate_presigned_put_url(
          "examplebucket",
          "a",
          expires_seconds=604801,
        ),
      )
    },
    "expires_seconds must be between 1 and 604800",
  )
}

///|
fn assert_presigned_url_rejected(
  f : () -> Unit raise,
  message : String,
) -> Unit raise {
  try {
    ignore(f())
    fail("expected invalid input")
  } catch {
    S3Error::InvalidInput(actual) => assert_eq(actual, message)
    _ => fail("expected invalid input")
  }
}

///|
test "signer controlled headers are filtered case insensitively" {
  let client = test_client(
    "https://examplebucket.s3.amazonaws.com",
    session_token="session-token",
  )
  let req = client.signed_request(
    Put,
    "examplebucket",
    "test.txt",
    body=b"hello",
    options=RequestOptions(
      headers={
        "Accept-Encoding": "gzip",
        "host": "wrong-host",
        "Transfer-Encoding": "chunked",
        "X-Amz-Date": "wrong-date",
        "X-Amz-Content-Sha256": "wrong-hash",
        "X-Amz-Security-Token": "wrong-token",
        "Authorization": "wrong-auth",
        "Content-Length": "5",
      },
      timestamp="20130524T000000Z",
      payload_hash="UNSIGNED-PAYLOAD",
    ),
  )
  assert_true(req.headers.get("Accept-Encoding") is Some("identity"))
  assert_true(req.headers.get("host") is None)
  assert_true(req.headers.get("Transfer-Encoding") is None)
  assert_true(req.headers.get("X-Amz-Date") is None)
  assert_true(req.headers.get("X-Amz-Content-Sha256") is None)
  assert_true(req.headers.get("X-Amz-Security-Token") is None)
  assert_eq(req.headers["Host"], "examplebucket.s3.amazonaws.com")
  assert_eq(req.headers["x-amz-date"], "20130524T000000Z")
  assert_eq(req.headers["x-amz-content-sha256"], "UNSIGNED-PAYLOAD")
  assert_eq(req.headers["x-amz-security-token"], "session-token")
  assert_eq(req.headers["Content-Length"], "5")
  assert_true(
    req.headers["Authorization"].contains(
      "SignedHeaders=accept-encoding;content-length;host;x-amz-content-sha256;x-amz-date;x-amz-security-token",
    ),
  )
}

///|
test "sigv4 header normalization collapses internal whitespace" {
  assert_eq(
    normalize_header_value(" \t alpha \t  beta   gamma \t "),
    "alpha beta gamma",
  )
}

///|
test "sigv4 canonical headers coalesce duplicate casing" {
  let (canonical, signed) = canonical_headers({
    "Content-Type": " text/plain ",
    "content-type": " application/json ",
    "X-Amz-Meta-Test": " one \t two ",
  })
  assert_eq(
    canonical, "content-type:text/plain,application/json\nx-amz-meta-test:one two\n",
  )
  assert_eq(signed, "content-type;x-amz-meta-test")
}

///|
test "ensure success response raises service error for list failures" {
  let response : @http.Response = {
    code: 403,
    reason: "Forbidden",
    headers: {},
    cookies: [],
  }
  try {
    ensure_success_response(
      response, "<Error><Code>AccessDenied</Code></Error>",
    )
    fail("expected service error")
  } catch {
    S3Error::ServiceError(err_response, body) => {
      assert_eq(err_response.code, 403)
      assert_eq(body, "<Error><Code>AccessDenied</Code></Error>")
    }
    _ => fail("expected S3 service error")
  }
}

///|
test "head error response raises service error without reading body" {
  let response : @http.Response = {
    code: 404,
    reason: "Not Found",
    headers: { "Content-Length": "123" },
    cookies: [],
  }
  try {
    raise_service_error_response_without_body(response)
    fail("expected service error")
  } catch {
    S3Error::ServiceError(err_response, body) => {
      assert_eq(err_response.code, 404)
      assert_eq(body, "")
    }
    _ => fail("expected S3 service error")
  }
}

///|
test "success response predicate accepts only 2xx responses" {
  let response : @http.Response = {
    code: 200,
    reason: "OK",
    headers: {},
    cookies: [],
  }
  assert_true(is_success_response(response))
  assert_true(
    is_success_response({ ..response, code: 204, reason: "No Content", }),
  )
  assert_true(!is_success_response({ ..response, code: 199, }))
  assert_true(!is_success_response({ ..response, code: 300, }))
  assert_true(
    !is_success_response({ ..response, code: 404, reason: "Not Found", }),
  )
}

///|
test "parse list objects v2 decodes xml entities" {
  let xml =
    #|<ListBucketResult>
    #|  <IsTruncated>false</IsTruncated>
    #|  <NextContinuationToken>next&amp;token&#13;</NextContinuationToken>
    #|  <Contents><Key>a&amp;b&lt;c&gt;&quot;d&apos;&#xD;.txt</Key><ETag>&quot;etag&amp;1&quot;</ETag><Size>7</Size></Contents>
    #|  <CommonPrefixes><Prefix>dir&amp;one&#x2F;</Prefix></CommonPrefixes>
    #|</ListBucketResult>
  let result = parse_list_objects_v2(xml)
  assert_true(result.next_continuation_token is Some("next&token\r"))
  assert_eq(result.contents[0].key, "a&b<c>\"d'\r.txt")
  assert_true(result.contents[0].etag is Some("\"etag&1\""))
  assert_eq(result.common_prefixes[0], "dir&one/")
}

///|
test "parse list objects v2 rejects invalid success responses" {
  let invalid_size =
    #|<ListBucketResult>
    #|  <IsTruncated>true</IsTruncated>
    #|  <Contents><Key>a.txt</Key><Size>bad</Size></Contents>
    #|</ListBucketResult>
  assert_invalid_response(
    invalid_size, "invalid integer for Contents.Size: bad",
  )
  let invalid_truncated =
    #|<ListBucketResult>
    #|  <IsTruncated>maybe</IsTruncated>
    #|</ListBucketResult>
  assert_invalid_response(
    invalid_truncated, "invalid boolean for IsTruncated: maybe",
  )
  let missing_key =
    #|<ListBucketResult>
    #|  <IsTruncated>false</IsTruncated>
    #|  <Contents><Size>1</Size></Contents>
    #|</ListBucketResult>
  assert_invalid_response(missing_key, "missing <Key> in Contents")
  let missing_prefix =
    #|<ListBucketResult>
    #|  <IsTruncated>false</IsTruncated>
    #|  <CommonPrefixes></CommonPrefixes>
    #|</ListBucketResult>
  assert_invalid_response(missing_prefix, "missing <Prefix> in CommonPrefixes")
  let missing_close =
    #|<ListBucketResult>
    #|  <IsTruncated>false
    #|</ListBucketResult>
  assert_invalid_response(missing_close, "missing closing tag </IsTruncated>")
}

///|
fn assert_invalid_response(xml : String, message : String) -> Unit raise {
  try {
    ignore(parse_list_objects_v2(xml))
    fail("expected invalid response")
  } catch {
    S3Error::InvalidResponse(actual) => assert_eq(actual, message)
    _ => fail("expected invalid response")
  }
}
