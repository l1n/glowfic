# frozen_string_literal: true

require 'securerandom'

# Takes a Vernier wall-clock profile of a random sample of requests and uploads
# it to S3, to see where request time goes in production.
#
# The rate is `PROFILE_SAMPLE_RATE`, a fraction of requests, and is 0 (off)
# unless set. It is capped at `MAX_RATE`. A config change restarts the dynos,
# so the rate can be raised or turned off without a deploy:
#
#   heroku config:set PROFILE_SAMPLE_RATE=0.01 -a vast-journey-9935
#
# Only one profile runs at a time in each Puma worker. Vernier samples every
# thread in the process, so a second profile would measure the same threads
# twice. A sampled request that finds a profile running is served normally
# and is not profiled.
#
# Profiles are written under `profiles/<date>/` in the icon bucket. That bucket
# is publicly readable, so each key ends in a random token and a profile holds
# only stack frames, the controller and action, and timings. It holds no user
# id, no query string and no header. Open one at https://profiler.firefox.com.
#
# Each profiled request gets a `profile_key` attribute in New Relic, so a slow
# transaction can be matched to its profile:
#
#   SELECT name, duration, profile_key FROM Transaction
#   WHERE profile_key IS NOT NULL SINCE 1 day ago
class ProfileSampler
  MAX_RATE = 0.05

  # One sample per millisecond. Vernier's default of 500 microseconds doubles
  # the overhead for detail that requests of 100ms and more do not need.
  INTERVAL_MICROSECONDS = 1000

  # Uploads wait here for the background thread. When it is full, a new
  # profile is dropped rather than letting profiles build up in memory.
  QUEUE_SIZE = 4

  def self.rate
    ENV['PROFILE_SAMPLE_RATE'].to_f.clamp(0.0, MAX_RATE)
  end

  def initialize(app, rate: self.class.rate, uploader: method(:upload))
    @app = app
    @rate = rate
    @uploader = uploader
    @lock = Mutex.new
  end

  def call(env)
    return @app.call(env) unless @rate.positive? && rand < @rate
    return @app.call(env) unless @lock.try_lock

    begin
      profile(env)
    ensure
      @lock.unlock
    end
  end

  private

  def profile(env)
    response = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Vernier.profile(interval: INTERVAL_MICROSECONDS, hooks: [:rails]) do
      response = @app.call(env)
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    enqueue(env, result, response.first, elapsed)
    response
  end

  # The request has its response by now. Anything that goes wrong with the
  # profile is logged and the response is returned unchanged.
  def enqueue(env, result, status, elapsed)
    key = object_key(env, status, elapsed)
    NewRelic::Agent.add_custom_attributes(profile_key: key) if defined?(NewRelic::Agent)
    uploads.push([key, result], true)
  rescue ThreadError
    Rails.logger.info("[profile_sampler] upload queue full, dropped #{key}")
  rescue StandardError => e
    Rails.logger.warn("[profile_sampler] #{e.class}: #{e.message}")
  end

  def object_key(env, status, elapsed)
    params = env['action_dispatch.request.path_parameters'] || {}
    action = [params[:controller], params[:action]].compact.join('#').presence || 'unrouted'
    now = Time.now.utc
    [
      'profiles',
      now.strftime('%Y-%m-%d'),
      "#{now.strftime('%H%M%S')}-#{action.tr('/#', '--')}-#{status}-#{(elapsed * 1000).round}ms-#{SecureRandom.hex(8)}.json.gz",
    ].join('/')
  end

  # Puma forks its workers after boot, and a thread does not survive a fork,
  # so each worker starts its own upload thread on its first profile.
  def uploads
    return @uploads if @uploads_pid == Process.pid
    @uploads_pid = Process.pid
    @uploads = SizedQueue.new(QUEUE_SIZE)
    queue = @uploads
    Thread.new do
      loop do
        key, result = queue.pop
        @uploader.call(key, result)
      rescue StandardError => e
        Rails.logger.warn("[profile_sampler] upload of #{key} failed: #{e.class}: #{e.message}")
      end
    end
    @uploads
  end

  def upload(key, result)
    S3_BUCKET.put_object(
      key: key,
      body: result.to_firefox(gzip: true),
      content_type: 'application/json',
      content_encoding: 'gzip',
    )
  end
end
