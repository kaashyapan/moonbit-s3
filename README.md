# hackwaly/s3

Async S3 client for MoonBit, built on `moonbitlang/async/http`.

This package supports the native backend.

```mbt nocheck
///|
async fn example {
  let client = @s3.Client(
    @s3.Config("us-east-1", @s3.Credentials("AKIA...", "secret...")),
  )
  let object = client.get_object("my-bucket", "path/to/object.txt")
  let body = object.body.read_all().text()
  object.body.close()
  println(body)
}
```

For MinIO or other S3-compatible services, use a custom endpoint and path-style
addressing:

```mbt nocheck
///|
let client = @s3.Client(
  @s3.Config(
    "us-east-1",
    @s3.Credentials("minioadmin", "minioadmin"),
    endpoint="http://127.0.0.1:9000",
    endpoint_style=@s3.Path,
  ),
)
```

Implemented operations:

- `get_object`
- `put_object`
- `head_object`
- `delete_object`
- `list_objects_v2`
