///|
test "credentials debug redacts secrets" {
  let credentials = Credentials(
    "AKIAIOSFODNN7EXAMPLE",
    "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    session_token="session-token",
  )
  let credentials_debug = Repr(credentials).to_string()
  assert_true(credentials_debug.contains("AKIAIOSFODNN7EXAMPLE"))
  assert_true(credentials_debug.contains("***"))
  assert_true(
    !credentials_debug.contains("wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
  )
  assert_true(!credentials_debug.contains("session-token"))
}

///|
test "endpoint style defaults follow the endpoint" {
  // No endpoint: AWS default URL, so virtual-host addressing.
  let aws = Config("us-east-1", Credentials("a", "b"))
  assert_true(aws.endpoint_style is VirtualHost)
  // Custom endpoint: third-party S3-compatible service, so path addressing.
  let custom = Config(
    "us-east-1",
    Credentials("a", "b"),
    endpoint="http://127.0.0.1:9000",
  )
  assert_true(custom.endpoint_style is Path)
  // An explicit style always wins over the inferred default.
  let forced = Config(
    "us-east-1",
    Credentials("a", "b"),
    endpoint="http://127.0.0.1:9000",
    endpoint_style=VirtualHost,
  )
  assert_true(forced.endpoint_style is VirtualHost)
}

///|
test "config debug redacts nested credential secrets" {
  let credentials = Credentials(
    "AKIAIOSFODNN7EXAMPLE",
    "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    session_token="session-token",
  )
  let config = Config("us-east-1", credentials)
  let config_debug = Repr(config).to_string()
  assert_true(config_debug.contains("AKIAIOSFODNN7EXAMPLE"))
  assert_true(config_debug.contains("***"))
  assert_true(
    !config_debug.contains("wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
  )
  assert_true(!config_debug.contains("session-token"))
}
