# frozen_string_literal: true

# `kill -URG <worker pid>` writes that process's heap to /tmp/heap-<dyno>-<pid>-<time>.json.
# Fetch it with `heroku ps:copy`. The dump holds string contents, so it stays on the dyno.
# The process pauses while it writes.
#
# HEAP_TRACE_ALLOCATIONS=web.2 records where each object is allocated on that dyno only.
# It makes requests slower and uses more memory.
require 'objspace'

module HeapDump
  def self.write
    path = "/tmp/heap-#{ENV.fetch('DYNO', 'local')}-#{Process.pid}-#{Time.now.utc.strftime('%H%M%S')}.json"
    GC.start
    File.open(path, 'w') { |file| ObjectSpace.dump_all(output: file) }
    gc = GC.stat.slice(:heap_live_slots, :heap_allocated_pages, :major_gc_count)
    Rails.logger.warn("[heap_dump] wrote #{path} (#{File.size(path) >> 20} MB) gc=#{gc.to_json}")
  rescue StandardError => e
    Rails.logger.warn("[heap_dump] failed: #{e.class}: #{e.message}")
  end
end

if Rails.env.production?
  Signal.trap('URG') { Thread.new { HeapDump.write } }
  ObjectSpace.trace_object_allocations_start if ENV['HEAP_TRACE_ALLOCATIONS'].to_s.split(',').include?(ENV['DYNO'])
end
