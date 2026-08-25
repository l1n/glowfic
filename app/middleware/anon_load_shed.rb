# frozen_string_literal: true

# Returns a 503 to non-logged-in users whose request has already been waiting
# in Puma's queue longer than `WAIT_THRESHOLD_SECONDS` by the time it gets a
# worker. Frees the worker to serve a logged-in request from the queue
# instead.
#
# This is a load-shedding layer that complements the steady-state rate limits
# in `config/initializers/rack_attack.rb`. Under normal load the queue wait
# is sub-100ms and this middleware passes everything through unchanged; it
# only triggers when the system is genuinely saturated (large queues, slow
# requests, dyno restart re-saturation). When that happens, anonymous
# traffic gets a fast 503 + Retry-After instead of being held in queue and
# eventually rack-timeout-aborted; logged-in traffic continues normally.
#
# `WAIT_THRESHOLD_SECONDS` is deliberately well above normal latency and
# well below `RACK_TIMEOUT_WAIT_TIMEOUT`, so anonymous users still get fast
# service in steady state, and only shed when the queue is actually deep
# enough that rack-timeout would have failed them in another few seconds
# anyway.
class AnonLoadShed
  WAIT_THRESHOLD_SECONDS = 5.0

  def initialize(app)
    @app = app
  end

  # The queue-wait check comes first because it is the cheapest and by far the
  # most common answer: in steady state nothing is saturated, so this costs one
  # env lookup and returns. Identifying the user means building a cookie jar to
  # verify a signature, which is only worth doing on the rare request we are
  # otherwise about to shed. All three checks are pass-throughs, so ordering
  # changes only the work done, never the verdict.
  def call(env)
    waited = wait_seconds(env)
    return @app.call(env) if waited.nil? || waited < WAIT_THRESHOLD_SECONDS
    return @app.call(env) if login_request?(env)
    return @app.call(env) if logged_in?(env)
    [
      503,
      { 'Content-Type' => 'text/plain', 'Retry-After' => '30' },
      ["Server busy, please try again shortly.\n"],
    ]
  end

  private

  def logged_in?(env)
    session_user_id(env).present? || permanent_user_id(env).present?
  end

  def session_user_id(env)
    session = env['rack.session']
    session && session[:user_id]
  end

  # Readers who ticked "remember me" carry their credential in a permanent
  # signed cookie rather than the session: the session cookie is configured
  # with no expiry, so it dies with the browser, and
  # `Authentication::Web#check_permanent_user` only promotes the cookie into
  # the session once a controller runs — which is after this middleware.
  #
  # Checking the session alone therefore reads a genuinely logged-in reader as
  # anonymous on their first request after a browser restart, and they cannot
  # retry their way out of it: a shed response never reaches the controller
  # that would have restored their session, so every refresh sheds again for
  # as long as the queue stays deep. Only /login, exempted above, breaks the
  # loop.
  #
  # The signature is verified rather than the cookie merely being checked for
  # presence, so a scraper cannot opt out of shedding by inventing a `user_id`
  # cookie. Building the jar is a bare HMAC check — no database work, and no
  # session is written, so a shed request still costs what it did before.
  def permanent_user_id(env)
    ActionDispatch::Request.new(env).cookie_jar.signed[:user_id]
  rescue StandardError
    # A malformed or unverifiable cookie is simply not a login; fall back to
    # the session verdict rather than letting a bad cookie raise a 500.
    nil
  end

  # A logged-out user has no way to become prioritized except by logging in, so
  # genuine login traffic must never be shed: let /login (both the form and the
  # POST) wait in the long queue instead. Spamming this path to dodge the shed
  # is bounded by the rack-attack throttle on POST /login, and our threat model
  # is scraping rather than login floods.
  def login_request?(env)
    env['PATH_INFO'] == '/login'
  end

  # rack-timeout stores its RequestDetails (including .wait, the seconds the
  # request spent in the dyno's queue before reaching a worker) under
  # Rack::Timeout::ENV_INFO_KEY. The gem is production-only, so resolve the
  # constant defensively: where it isn't loaded there is no queue-wait info
  # and we never shed.
  def wait_seconds(env)
    return nil unless defined?(Rack::Timeout::ENV_INFO_KEY)
    env[Rack::Timeout::ENV_INFO_KEY]&.wait
  end
end
