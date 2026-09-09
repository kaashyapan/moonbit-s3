///|
/// Live integration check for the S3 client against a real S3-compatible
/// server (MinIO). Run with:
///   moon run src/livecheck -- <url> <access-key> <secret-key> <region>
async fn main {
  let args = @env.args()
  guard args.length() >= 5 else {
    println(
      "usage: moon run src/livecheck -- <url> <access-key> <secret-key> <region>",
    )
    return
  }
  let url = args[1]
  let access_key = args[2]
  let secret_key = args[3]
  let region = args[4]
  let client = @s3.Client(
    @s3.Config(
      region,
      @s3.Credentials(access_key, secret_key),
      endpoint=url,
      endpoint_style=@s3.Path,
    ),
  )
  let bucket = "kaashyapan-s3-livecheck"
  let key = "livecheck/hello.txt"
  let content = "Hello MinIO from MoonBit!"

  println("=== 1. list_buckets ===")
  let buckets = client.list_buckets()
  println("bucket count: \{buckets.buckets.length()}")
  for b in buckets.buckets {
    println("  - \{b.name} (created \{Repr(b.creation_date)})")
  }
  assert_true(buckets.owner_id is Some(_))

  println("=== 2. create_bucket ===")
  ignore(client.create_bucket(bucket)) catch {
    @s3.S3Error::ServiceError(response, body) =>
      println("create_bucket: \{response.code} \{body}")
    _ => fail("unexpected error in create_bucket")
  }

  println("=== 3. head_bucket ===")
  let head_bucket_response = client.head_bucket(bucket)
  println("head_bucket: \{head_bucket_response.code}")

  println("=== 4. put_object ===")
  let put_response = client.put_object(bucket, key, content)
  println("put_object: \{put_response.code}")

  println("=== 5. head_object ===")
  let head_response = client.head_object(bucket, key)
  println("head_object: \{head_response.code}")
  println(
    "  Content-Length: \{Repr(head_response.headers.get("Content-Length"))}",
  )
  println("  ETag: \{Repr(head_response.headers.get("ETag"))}")
  println("  Content-Type: \{Repr(head_response.headers.get("Content-Type"))}")

  println("=== 6. get_object ===")
  let object = client.get_object(bucket, key)
  println("get_object: \{object.response.code}")
  let body = @io.Reader::read_all(object.body).text()
  object.body.close()
  assert_eq(body, content)
  println("  body matches: \{body}")

  println("=== 7. list_objects_v2 ===")
  let listed = client.list_objects_v2(bucket, prefix="livecheck/")
  assert_eq(listed.contents.length(), 1)
  assert_eq(listed.contents[0].key, key)
  assert_eq(listed.contents[0].size, content.length().to_int64())
  println("  key: \{listed.contents[0].key}")
  println("  size: \{listed.contents[0].size}")
  println("  etag: \{Repr(listed.contents[0].etag)}")

  println("=== 8. presigned GET URL ===")
  let presigned = client.generate_presigned_get_url(bucket, key)
  println("  url: \{presigned}")
  let (origin, target) = split_url(presigned)
  let unsigned = @http.Client(origin)
  unsigned.request(@http.Get, target)
  let presigned_response = unsigned.end_request()
  let presigned_body = unsigned.read_all().text()
  unsigned.close()
  assert_eq(presigned_response.code, 200)
  assert_eq(presigned_body, content)
  println("  presigned GET: \{presigned_response.code}, body matches")

  println("=== 9. presigned PUT URL ===")
  let put_url = client.generate_presigned_put_url(
    bucket, "livecheck/presigned-put.txt",
  )
  let (put_origin, put_target) = split_url(put_url)
  let put_unsigned = @http.Client(put_origin)
  put_unsigned.request(@http.Put, put_target, extra_headers={
    "Content-Length": content.length().to_string(),
  })
  put_unsigned.write(content)
  let presigned_put_response = put_unsigned.end_request()
  let put_error_body = put_unsigned.read_all().text()
  put_unsigned.close()
  println("  presigned PUT: \{presigned_put_response.code} \{put_error_body}")
  assert_eq(presigned_put_response.code, 200)
  let verified = client.head_object(bucket, "livecheck/presigned-put.txt")
  println(
    "  uploaded via presigned PUT, Content-Length: \{Repr(verified.headers.get("Content-Length"))}",
  )

  println("=== 10. negative: unsigned request is rejected ===")
  let rejected = @http.Client(url)
  rejected.request(@http.Get, "/\{bucket}/\{key}")
  let rejected_response = rejected.end_request()
  rejected.close()
  assert_eq(rejected_response.code, 403)
  println("  unsigned GET: \{rejected_response.code} (403 expected)")

  println("=== 11. negative: head_object on missing key raises 404 ===")
  ignore(client.head_object(bucket, "livecheck/missing.txt")) catch {
    @s3.S3Error::ServiceError(response, _) => {
      assert_eq(response.code, 404)
      println("  missing key: \{response.code} (404 expected)")
    }
    _ => fail("unexpected error for missing key")
  }

  println("=== 12. cleanup: delete_object + delete_bucket ===")
  let delete_response = client.delete_object(bucket, key)
  assert_eq(delete_response.code, 204)
  let delete_presigned = client.delete_object(
    bucket, "livecheck/presigned-put.txt",
  )
  assert_eq(delete_presigned.code, 204)
  let delete_bucket_response = client.delete_bucket(bucket)
  println("  delete_object: \{delete_response.code}")
  println("  delete_object (presigned put): \{delete_presigned.code}")
  println("  delete_bucket: \{delete_bucket_response.code}")

  println("=== live check passed ===")
}

///|
/// Split a URL of the form `scheme://host[:port]/path?query` into
/// `(origin, path_and_query)`.
fn split_url(url : String) -> (String, String) raise {
  let separator = "://"
  guard url.find(separator) is Some(index) else { fail("not a url: \{url}") }
  let rest = url[index + separator.length():]
  let mut split : Int = rest.length()
  for i, c in rest.to_array() {
    if c == '/' {
      split = i
      break
    }
  }
  let origin = url[:index].to_owned() + "://" + rest[:split].to_owned()
  (origin, rest[split:].to_owned())
}
