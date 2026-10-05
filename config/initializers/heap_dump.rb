# frozen_string_literal: true

# `kill -PWR <worker pid>` logs one [heap_stats] line: GC heap, Ruby object sizes, jemalloc
# counters and RSS, to show how much memory Ruby objects account for and what is native.
#
# `kill -URG <worker pid>` also writes that process's heap to /tmp/heap-<dyno>-<pid>-<time>.json.
# Fetch it with `heroku ps:copy`. The dump holds string contents, so it stays on the dyno.
# The process pauses while it writes.
#
# HEAP_TRACE_ALLOCATIONS=web.2 records where each object is allocated on that dyno only.
# It makes requests slower and uses more memory.
require 'fiddle'
require 'objspace'

module HeapDump
  JEMALLOC_STATS = %w(allocated active metadata resident mapped retained).freeze

  def self.write
    path = "/tmp/heap-#{ENV.fetch('DYNO', 'local')}-#{Process.pid}-#{Time.now.utc.strftime('%H%M%S')}.json"
    GC.start
    File.open(path, 'w') { |file| ObjectSpace.dump_all(output: file) }
    Rails.logger.warn("[heap_dump] wrote #{path} (#{File.size(path) >> 20} MB)")
    log_stats
  rescue StandardError => e
    Rails.logger.warn("[heap_dump] failed: #{e.class}: #{e.message}")
  end

  def self.log_stats
    Rails.logger.warn("[heap_stats] #{stats.to_json}")
  rescue StandardError => e
    Rails.logger.warn("[heap_stats] failed: #{e.class}: #{e.message}")
  end

  # Sizes in MB.
  def self.stats
    gc = GC.stat
    slot_bytes = GC.stat_heap.values.sum { |heap| heap[:heap_eden_slots] * heap[:slot_size] }
    {
      dyno: ENV.fetch('DYNO', 'local'),
      pid: Process.pid,
      rss: proc_status('VmRSS'),
      rss_anon: proc_status('RssAnon'),
      gc_pages: mb(gc[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE]),
      gc_slots: mb(slot_bytes),
      live_slots: gc[:heap_live_slots],
      free_slots: gc[:heap_free_slots],
      # Leaves out internal objects such as compiled code; a dump counts those.
      visible_objects: mb(ObjectSpace.memsize_of_all),
      malloc_increase: mb(gc[:malloc_increase_bytes]),
      jemalloc: jemalloc_stats,
    }
  end

  def self.proc_status(field)
    line = File.foreach('/proc/self/status').find { |l| l.start_with?("#{field}:") }
    line && (line.split[1].to_i / 1024.0).round(1)
  end

  def self.mb(bytes)
    (bytes / 1_048_576.0).round(1)
  end

  def self.jemalloc_stats
    mallctl = Fiddle::Function.new(
      Fiddle::Handle::DEFAULT['mallctl'],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
      Fiddle::TYPE_INT,
    )
    epoch = Fiddle::Pointer[[1].pack('Q')]
    mallctl.call('epoch', nil, nil, epoch, 8)
    stats = JEMALLOC_STATS.index_with { |name| mb(read_ctl(mallctl, "stats.#{name}", 8, 'Q')) }
    stats.merge('narenas' => read_ctl(mallctl, 'arenas.narenas', 4, 'L'))
  rescue Fiddle::DLError
    nil
  end

  def self.read_ctl(mallctl, name, size, format)
    value = Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE)
    length = Fiddle::Pointer[[size].pack('Q')]
    return nil unless mallctl.call(name, value, length, nil, 0).zero?
    value[0, size].unpack1(format)
  end
end

if Rails.env.production?
  Signal.trap('URG') { Thread.new { HeapDump.write } }
  Signal.trap('PWR') { Thread.new { HeapDump.log_stats } }
  ObjectSpace.trace_object_allocations_start if ENV['HEAP_TRACE_ALLOCATIONS'].to_s.split(',').include?(ENV['DYNO'])
end
