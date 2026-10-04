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
# `WAIT_THRESHOLD_SECONDS` was 5s until 2026-10. At 5s the queue never had to
# drain for anyone: in the week to 2026-10-04, logged-in pages took 0.1-0.25s
# to serve at the median but waited 0.7-1.6s in the queue first, and over 5s
# at p95, behind anonymous traffic that was never shed until it had already
# waited 5s. Shedding anonymous readers at 1s keeps the queue short enough
# that logged-in users are not stuck in it. Logged-in users are never shed.
#
# Since `no_cookie` (below) puts nearly all of the scrape on the scraper
# threshold, a logged-out reader who has been here before gets 2s.
#
# `ANON_SHED_WAIT_SECONDS` sets it without a deploy (a config change restarts
# the dynos), e.g. back to 5 if logged-out readers are shed too often. It is
# kept between the scraper threshold below and rack-timeout's wait timeout.
class AnonLoadShed
  WAIT_THRESHOLD_SECONDS = ENV.fetch('ANON_SHED_WAIT_SECONDS', '2.0').to_f.clamp(0.5, 15.0)

  # Requests that look like the distributed scrape are shed an order of
  # magnitude sooner, so that when the queue does back up it is the scraper
  # that loses its thread slot rather than whichever reader happened to arrive
  # at the same moment.
  #
  # In the seven days to 2026-09-09 the scrape was 9.7M of the 12.5M HTML
  # navigations and 469 of the 594 dyno-hours spent serving them, while 65,595
  # genuine page loads (2.4%) were shed as collateral. Both classes were
  # competing on the same 5s threshold, so the shedder was splitting the
  # damage between them instead of aiming it.
  #
  # This is still a threshold and not a block: below it, scraper-shaped
  # traffic is served exactly as before. It only bites once the queue is deep
  # enough that somebody is going to be shed regardless, and it decides who.
  SCRAPER_WAIT_THRESHOLD_SECONDS = 0.5

  # Turns the Fetch Metadata and client-hint checks in `scraper_signal` on or
  # off. Setting `ANON_SHED_SEC_FETCH=off` falls back to the signed-exchange
  # test alone, without a deploy (a config change restarts the dynos).
  SEC_FETCH_TEST = ENV.fetch('ANON_SHED_SEC_FETCH', 'on') != 'off'

  # Turns the `no_cookie` signal on or off. `ANON_SHED_NO_COOKIE=off` turns it
  # off without a deploy.
  NO_COOKIE_TEST = ENV.fetch('ANON_SHED_NO_COOKIE', 'on') != 'off'

  # Chrome has sent `Sec-CH-UA` on every secure request since 89. Older
  # builds are left to the Fetch Metadata check only.
  CLIENT_HINTS_SINCE = 90

  def initialize(app)
    @app = app
  end

  # The checks are ordered cheapest-first, because each one is a pass-through:
  # ordering changes only the work done on the way to a verdict, never the
  # verdict itself.
  #
  # The queue-wait check leads because it is both the cheapest and by far the
  # most common answer — in steady state nothing is saturated, so this costs
  # one env lookup and returns. The shape check comes next at a handful of
  # header string comparisons, and only runs on requests already waiting long
  # enough to be worth classifying. Identifying the user comes last because it means
  # building a cookie jar to verify a signature, which is only worth doing on
  # the rare request we are otherwise about to shed.
  def call(env)
    waited = wait_seconds(env)
    return @app.call(env) if waited.nil? || waited < SCRAPER_WAIT_THRESHOLD_SECONDS
    return @app.call(env) if waited < WAIT_THRESHOLD_SECONDS && !self.class.scraper_signal(env)
    return @app.call(env) if login_request?(env)
    return @app.call(env) if safe_ip?(env)
    return @app.call(env) if logged_in?(env)
    record_shed(env)
    [
      503,
      { 'Content-Type' => 'text/plain', 'Retry-After' => '30' },
      ["Server busy, please try again shortly.\n"],
    ]
  end

  # Returns why a request looks like the distributed scrape, or nil if it
  # does not. It is a class method so that `ClientFingerprint` can record the
  # verdict on every request, not only on those that waited long enough for
  # this middleware to ask.
  #
  # The test applies only to HTML navigations from a client that says it is
  # Chrome (or another Chromium browser, which all carry `Chrome/` in the UA).
  # Firefox and Safari send none of the headers checked below, so a request
  # that does not claim Chrome is never classified. Subresources carry a
  # different Accept and are judged with their page, not apart from it.
  #
  # The signals, in order:
  #
  # - `no_sxg`: no `application/signed-exchange` in Accept. Genuine Chrome
  #   120-141 sent it on 95-100% of navigations; the scrape's forged UAs on
  #   0.0-0.3%. By 2026-10-01 the scrape had copied a real Chrome Accept
  #   byte for byte (1.3M of 1.84M requests on one Chrome/145 Mac UA string in
  #   a week), so this signal alone no longer catches most of it.
  # - `no_sec_fetch`: no `Sec-Fetch-Mode`. Chromium has sent Fetch Metadata on
  #   every request since 76. These headers are specified behaviour, so they
  #   are less likely to change under us than the Accept token was.
  # - `no_ch_ua`: no `Sec-CH-UA`. Chromium sends this low-entropy client hint
  #   on every secure request since 89.
  # - `ch_ua_mismatch`: `Sec-CH-UA` names a Chromium version other than the
  #   one in the UA. The scrape rotates its UA across many Chrome versions; a
  #   client that copied one browser's header set keeps that browser's hint.
  #   Every Chromium browser lists a `"Chromium"` brand whose major version
  #   matches the `Chrome/` token in its UA.
  #
  # Android WebView (`; wv)` in the UA) is held only to the Fetch Metadata
  # check. Readers arrive in it from in-app browsers, and older WebView builds
  # did not send client hints.
  #
  # This is a header-level heuristic, which is the most forgeable tier there
  # is. It sets a threshold rather than a block for that reason: a client
  # that copies a full, consistent header set gets the reader threshold.
  def self.scraper_signal(env)
    accept = env['HTTP_ACCEPT'].to_s
    (accept.start_with?('text/html') && chrome_signal(env, accept)) || cookie_signal(env)
  end

  # `no_cookie`: no cookie at all. Every logged-out page sets a session
  # cookie, so a reader sends one from their second page on. The scrape never
  # does: on 2026-10-04, 35,559 requests in 5.5 minutes came from 32,950 IPs,
  # 31,554 of which made one request, and 98% of logged-out HTML requests had
  # no cookie, against 3% of logged-in ones. A reader who followed a link from
  # another site (`Sec-Fetch-Site: cross-site`) is not counted, so a first
  # visit from Discord or Tumblr keeps the reader threshold. A first visit
  # typed in or from a bookmark does not; that reader is shed early only while
  # the site is saturated, and only on that first page.
  #
  # Unlike the browser-header signals, this does not require an HTML Accept.
  # Most of the scrape sends `Accept: */*`, which no browser sends for a page,
  # and that let it pass every other signal as a reader. The API is left out:
  # its clients authenticate with a header and send no cookie.
  def self.cookie_signal(env)
    return nil unless NO_COOKIE_TEST
    return nil unless env['REQUEST_METHOD'] == 'GET'
    return nil if env['PATH_INFO'].to_s.start_with?('/api/')
    return nil if env['HTTP_COOKIE'].present?
    return nil if env['HTTP_SEC_FETCH_SITE'] == 'cross-site'
    'no_cookie'
  end

  def self.chrome_signal(env, accept)
    user_agent = env['HTTP_USER_AGENT'].to_s
    major = user_agent[/Chrome\/(\d+)/, 1]
    return nil unless major
    return 'no_sxg' unless accept.include?('signed-exchange')
    return nil unless SEC_FETCH_TEST
    return 'no_sec_fetch' if env['HTTP_SEC_FETCH_MODE'].blank?
    return nil if user_agent.include?('; wv)') || major.to_i < CLIENT_HINTS_SINCE
    client_hint = env['HTTP_SEC_CH_UA']
    return 'no_ch_ua' if client_hint.blank?
    return 'ch_ua_mismatch' unless client_hint.include?(%("Chromium";v="#{major}"))
    nil
  end

  # The agent keeps a metric recorded inside a transaction with that
  # transaction, and discards both when the transaction is ignored. So shed
  # counts are held here and handed to the agent every `FLUSH_SECONDS` from a
  # thread that is not inside a transaction.
  FLUSH_SECONDS = 60

  @shed_counts = Hash.new(0)
  @shed_lock = Mutex.new

  def self.count_shed(name)
    @shed_lock.synchronize do
      start_flusher unless @flusher_pid == Process.pid
      @shed_counts[name] += 1
    end
  end

  def self.flush_shed_counts
    counts = @shed_lock.synchronize do
      taken = @shed_counts
      @shed_counts = Hash.new(0)
      taken
    end
    counts.each { |name, count| NewRelic::Agent.increment_metric(name, count) }
  end

  # Puma forks its workers after boot, and a thread does not survive a fork,
  # so each worker starts its own flusher.
  def self.start_flusher
    @flusher_pid = Process.pid
    @shed_counts = Hash.new(0)
    Thread.new do
      loop do
        sleep FLUSH_SECONDS
        flush_shed_counts
      rescue StandardError => e
        Rails.logger.warn("[anon_load_shed] flush failed: #{e.class}: #{e.message}")
      end
    end
  end
  private_class_method :start_flusher, :chrome_signal, :cookie_signal

  private

  # A shed request is counted, not traced. During saturation 11-13% of all
  # requests are shed, and a full Transaction event for each one was a large
  # share of New Relic ingest while saying nothing a counter does not. Query
  # the counts with
  #
  #   SELECT sum(newrelic.timeslice.value) FROM Metric
  #   WHERE metricTimesliceName LIKE 'Custom/AnonLoadShed/%'
  #   FACET metricTimesliceName TIMESERIES
  #
  # The name says why the request was shed: a scraper signal from
  # `scraper_signal`, or `reader` for one that waited past the reader
  # threshold.
  def record_shed(env)
    return unless defined?(NewRelic::Agent)
    NewRelic::Agent.ignore_transaction
    self.class.count_shed("Custom/AnonLoadShed/#{self.class.scraper_signal(env) || 'reader'}")
  rescue StandardError
    # Telemetry must never turn a shed into a 500.
    nil
  end

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
  # Addresses in `RACK_ATTACK_SAFE_IP` (see config/initializers/rack_attack.rb),
  # such as the projectlawful reader proxy, which fetches on behalf of
  # readers and was being shed as one anonymous client. The IP is read the way
  # Rack::Attack reads it.
  def safe_ip?(env)
    $safe_ips.present? && $safe_ips.include?(Rack::Request.new(env).ip)
  end

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
