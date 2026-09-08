///|
fn sha256_data_hex(data : &@io.Data) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(data.binary()))
}

///|
fn method_name(meth : S3Method) -> String {
  match meth {
    Get => "GET"
    Head => "HEAD"
    Put => "PUT"
    Delete => "DELETE"
  }
}

///|
fn to_sigv4_credentials(credentials : Credentials) -> @sigv4.Credentials {
  match credentials.session_token {
    Some(token) =>
      @sigv4.Credentials(
        credentials.access_key_id,
        credentials.secret_access_key,
        session_token=token,
      )
    None =>
      @sigv4.Credentials(
        credentials.access_key_id,
        credentials.secret_access_key,
      )
  }
}
