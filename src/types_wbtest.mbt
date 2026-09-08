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
