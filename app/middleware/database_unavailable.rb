# frozen_string_literal: true

# Answers a request with 503 rather than 500 when the database has gone away
# underneath it.
#
# Heroku Postgres restarts and fails over on its own schedule — twice in the
# 90 days to 2026-09-09 — and each event takes the connection away for two to
# five minutes. Requests in flight raise out of the adapter, and every one of
# them renders the generic 500 page: of the 3,861 500s served in the three
# weeks to 2026-09-09, 3,841 came from those two windows, overwhelmingly on
# /posts/:id.
#
# 500 is the wrong answer to "the database is restarting". It tells a browser
# the page is broken and tells a crawler the URL is broken, when the truth is
# "come back in half a minute" — which is what 503 plus Retry-After says, and
# what crawlers act on instead of dropping the URL. Nothing here needs an
# operator: the pool heals itself once Postgres is back, via the reaping and
# connect timeouts in config/database.yml. The failure just needs to stop
# lying about what it was.
#
# This sits innermost in the stack (see config/application.rb), which puts it
# inside ActionDispatch::ShowExceptions — so it gets the exception first and
# ShowExceptions never sees it — and outside ExceptionNotification::Rack, so
# the exception mail still goes out as it does today.
class DatabaseUnavailable
  RETRY_AFTER_SECONDS = 30
  PAGE = 'public/503.html'

  # ConnectionNotEstablished covers both failure modes actually observed:
  # DatabaseConnectionError, where Postgres is reachable but rejects our
  # credentials mid-failover, and the plain refused or timed-out connect while
  # it is down. It also covers ConnectionTimeoutError, where the database is
  # healthy but every pooled connection is checked out — equally transient,
  # equally a 503.
  #
  # ConnectionFailed is the mid-query case: the connection was good at
  # checkout and died partway through the statement.
  #
  # Deliberately excluded is the rest of StatementInvalid, including
  # NoDatabaseError. Those mean the query or the configuration is wrong, which
  # retrying will never fix, so they must keep reaching the 500 page and the
  # exception mail where someone will look at them.
  RESCUED_ERRORS = [
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::ConnectionFailed,
  ].freeze

  # Read at boot rather than per request: the whole point of this middleware
  # is the moments when the app is least able to absorb extra work, and a
  # missing page should break a deploy loudly rather than surface as a second
  # failure in the middle of an outage.
  def initialize(app)
    @app = app
    @body = Rails.root.join(PAGE).read.freeze
  end

  def call(env)
    @app.call(env)
  rescue *RESCUED_ERRORS => e
    report(e, env)
    [503, headers, [@body]]
  end

  private

  # Rack 3 specifies header names as lowercase, and the middleware wrapping
  # this one looks them up that way: Rack::ETag reads 'cache-control' before
  # deciding whether to add its own, Rack::Deflater reads 'content-encoding'.
  # Capitalised keys are not found by either, so they would quietly add
  # conflicting headers to a response that has already stated its intent.
  def headers
    {
      'content-type'  => 'text/html; charset=utf-8',
      'retry-after'   => RETRY_AFTER_SECONDS.to_s,
      # An error page cached at any layer outlives the outage that produced
      # it, so this response must never be stored or revalidated against.
      'cache-control' => 'no-store',
    }
  end

  # A swallowed exception is an invisible one, and these outages are only ever
  # diagnosable afterwards — New Relic's TransactionError records are how the
  # September events were reconstructed at all. Reporting explicitly means the
  # 503 costs nothing in visibility against the 500 it replaces.
  #
  # Reporting is itself guarded: an agent that raises here would turn the 503
  # back into the 500 this exists to prevent, at exactly the moment that
  # matters most.
  def report(error, env)
    NewRelic::Agent.notice_error(error) if defined?(NewRelic::Agent)
    Rails.logger&.error("Database unavailable, served 503 for #{env['PATH_INFO']}: #{error.class}: #{error.message}")
  rescue StandardError
    nil
  end
end
