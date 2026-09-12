module EnvHelper
  # Stubs one environment variable and leaves every other read alone.
  #
  # `allow(ENV).to receive(:[]).with('KEY')` looks like it constrains the stub
  # to one key. It does not: it replaces `ENV#[]` wholesale and then declares
  # that the only argument it will accept is that key. Any other `ENV[...]`
  # during the example fails with "received :[] with unexpected arguments",
  # and the code under test does not stop reading the environment just because
  # a spec is interested in one variable.
  #
  # Rack's multipart parser is the live example: it reads
  # RACK_MULTIPART_BUFFERED_UPLOAD_BYTESIZE_LIMIT (rack/multipart/parser.rb)
  # while parsing a form POST. Whether that read lands inside a stubbed
  # example depends on which worker runs the spec and what ran before it in
  # the same process, so the failure appears and disappears between runs.
  #
  # Installing the passthrough first keeps the stub to the one key it names.
  def stub_env(key, value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with(key).and_return(value)
  end
end
