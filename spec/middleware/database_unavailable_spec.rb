RSpec.describe DatabaseUnavailable do
  let(:downstream) { ->(_env) { [200, {}, ['ok']] } }
  let(:middleware) { DatabaseUnavailable.new(downstream) }

  def env(path: '/posts/1')
    { 'PATH_INFO' => path }
  end

  # Every error the middleware answers rather than re-raises, one per failure
  # mode seen in production. They are listed by construction rather than by
  # class so the spec exercises the same ancestry lookup `rescue` does.
  def raising(error)
    DatabaseUnavailable.new(->(_env) { raise error })
  end

  it "passes a healthy response through untouched" do
    expect(middleware.call(env)).to eq([200, {}, ['ok']])
  end

  describe "the failure modes it answers" do
    # Postgres refused the socket outright: the window where the server is
    # down and not yet listening again.
    it "answers a refused connection" do
      status, = raising(ActiveRecord::ConnectionNotEstablished.new('connection refused')).call(env)
      expect(status).to eq(503)
    end

    # Postgres was reachable but rejected our credentials, which is what a
    # failover looks like from here — the 2026-09-03 event.
    it "answers a rejected login" do
      status, = raising(ActiveRecord::DatabaseConnectionError.new('username: uag11qh4pgl9u2')).call(env)
      expect(status).to eq(503)
    end

    # The database is healthy but every pooled connection is checked out.
    # Transient for the same reason and worth the same answer.
    it "answers pool exhaustion" do
      status, = raising(ActiveRecord::ConnectionTimeoutError.new('could not obtain a connection')).call(env)
      expect(status).to eq(503)
    end

    # The connection was good at checkout and died mid-statement.
    it "answers a connection lost mid-query" do
      status, = raising(ActiveRecord::ConnectionFailed.new('server closed the connection unexpectedly')).call(env)
      expect(status).to eq(503)
    end
  end

  # A broken query and a missing database are not transient, and retrying will
  # never fix either. They have to keep reaching the 500 page and the exception
  # mail, or a real bug becomes a silently retried 503 forever.
  describe "the failures it deliberately leaves alone" do
    it "re-raises an invalid statement" do
      expect { raising(ActiveRecord::StatementInvalid.new('syntax error')).call(env) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end

    it "re-raises a missing database" do
      expect { raising(ActiveRecord::NoDatabaseError.new('does not exist')).call(env) }
        .to raise_error(ActiveRecord::NoDatabaseError)
    end

    it "re-raises anything unrelated to the database" do
      expect { raising(ArgumentError.new('bad')).call(env) }.to raise_error(ArgumentError)
    end
  end

  describe "the response" do
    let(:response) { raising(ActiveRecord::ConnectionNotEstablished.new('down')).call(env) }
    let(:headers) { response[1] }

    it "tells the client when to come back" do
      expect(headers['retry-after']).to eq(DatabaseUnavailable::RETRY_AFTER_SECONDS.to_s)
    end

    # An error page cached anywhere outlives the outage that produced it.
    it "is never stored" do
      expect(headers['cache-control']).to eq('no-store')
    end

    # Rack 3 specifies lowercase header names, and Rack::ETag and
    # Rack::Deflater — both of which wrap this middleware — look them up that
    # way. Capitalised keys would be missed and duplicated by those.
    it "names its headers the way the surrounding Rack middleware reads them" do
      expect(headers.keys).to all(satisfy { |key| key == key.downcase })
    end

    it "serves the static page rather than anything needing the database" do
      expect(response[2].first).to eq(Rails.root.join(DatabaseUnavailable::PAGE).read)
    end

    it "serves it as html" do
      expect(headers['content-type']).to eq('text/html; charset=utf-8')
    end
  end

  # These outages are only diagnosable after the fact, so the 503 must not cost
  # the visibility the 500 had: New Relic's error records are how the September
  # events were reconstructed at all.
  describe "reporting" do
    let(:error) { ActiveRecord::ConnectionNotEstablished.new('down') }

    it "still reports the error it swallowed" do
      expect(NewRelic::Agent).to receive(:notice_error).with(error)
      raising(error).call(env)
    end

    it "logs the path that failed" do
      expect(Rails.logger).to receive(:error).with(/posts\/64225/)
      raising(error).call(env(path: '/posts/64225'))
    end

    # A reporting agent that raises here would turn the 503 back into the 500
    # this middleware exists to prevent, at the moment that matters most.
    it "still answers 503 when reporting itself fails" do
      allow(NewRelic::Agent).to receive(:notice_error).and_raise(StandardError)
      status, = raising(error).call(env)
      expect(status).to eq(503)
    end
  end
end
