# frozen_string_literal: true

require "test_helper"

class TestRactorPool < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil RactorPool::VERSION
  end

  def test_multiple_pools_run_independently
    results1 = []
    results2 = []
    worker1 = ->(work) { work * 2 }
    worker2 = ->(work) { work * 3 }
    pool1 = RactorPool.new(worker: worker1, strategy: :coordinator, name: self.class.name) { |result| results1 << result }
    pool2 = RactorPool.new(worker: worker2, strategy: :round_robin, name: self.class.name) { |result| results2 << result }

    5.times { |index| pool1 << index }
    5.times { |index| pool2 << index }
    pool1.shutdown
    pool2.shutdown

    assert_equal [0, 2, 4, 6, 8], results1.sort
    assert_equal [0, 3, 6, 9, 12], results2.sort
  end

  def test_raises_when_strategy_is_invalid
    error = assert_raises(ArgumentError) do
      RactorPool.new(worker: proc { }, strategy: :nonsense, name: self.class.name)
    end

    assert_match "strategy must be", error.message
  end
end

module RactorPoolStrategyTests
  def test_init_default_size
    pool = RactorPool.new(worker: proc { }, strategy: strategy, name: self.class.name) { }
    Thread.pass
    assert_equal expected_default_ractor_count, Ractor.count
    main_thread = Thread.current
    threads = Thread.list.select { it == main_thread || it.name }
    assert_equal 1 + 2, threads.size # main thread, error collector thread, collector thread
    assert_equal [
      "RactorPool collector thread for #{self.class.name}",
      "RactorPool error collector thread for #{self.class.name}"
    ], threads.select(&:name).map(&:name).sort
    pool.shutdown
  end

  def test_init_size_one
    pool = RactorPool.new(size: 1, worker: proc { }, strategy: strategy, name: self.class.name) { }
    Thread.pass
    assert_equal 1 + 1, Ractor.count # main ractor, worker ractor
    main_thread = Thread.current
    threads = Thread.list.select { it == main_thread || it.name }
    assert_equal 1 + 2, threads.size # main thread, error collector thread, collector thread
    assert_equal [
      "RactorPool collector thread for #{self.class.name}",
      "RactorPool error collector thread for #{self.class.name}"
    ], threads.select(&:name).map(&:name).sort
    pool.shutdown
  end

  def test_init_size_greater_than_one
    pool = RactorPool.new(size: 2, worker: proc { }, strategy: strategy, name: self.class.name) { }
    Thread.pass
    assert_equal expected_size_two_ractor_count, Ractor.count
    main_thread = Thread.current
    threads = Thread.list.select { it == main_thread || it.name }
    assert_equal 1 + 2, threads.size # main thread, error collector thread, collector thread
    assert_equal [
      "RactorPool collector thread for #{self.class.name}",
      "RactorPool error collector thread for #{self.class.name}"
    ], threads.select(&:name).map(&:name).sort
    pool.shutdown
  end

  def test_names_worker_ractor_threads
    results = []
    worker = proc { |_work| Thread.current.name }
    pool = RactorPool.new(size: 2, worker: worker, strategy: strategy, name: self.class.name) { |name| results << name }

    4.times { |index| pool << index }
    pool.shutdown

    assert_equal [
      "RactorPool worker thread 0 for #{self.class.name}",
      "RactorPool worker thread 1 for #{self.class.name}"
    ], results.uniq.sort
  end

  def test_processes_work_items
    results = []
    worker = ->(work) { work * 2 }
    pool = RactorPool.new(worker: worker, strategy: strategy, name: self.class.name) { |result| results << result }

    5.times { |index| pool << index }
    pool.shutdown

    assert_equal 5, results.size
    assert_equal [0, 2, 4, 6, 8], results.sort
  end

  def test_processes_work_items_without_result_handler
    counter = Atom.new(0)
    worker = proc do |work|
      counter.swap { |value| value + 1 }
      work * 2
    end
    pool = RactorPool.new(worker: worker, strategy: strategy, name: self.class.name)

    5.times { |index| pool << index }
    pool.shutdown

    assert_equal 5, counter.value
  end

  def test_completes_queued_work_items_before_shutdown
    results = []
    worker = proc do |work|
      sleep(0.1)
      work * 2
    end
    pool = RactorPool.new(worker: worker, strategy: strategy, name: self.class.name) { |result| results << result }

    10.times { |index| pool << index }
    pool.shutdown

    assert_equal 10, results.size
    assert_equal [0, 2, 4, 6, 8, 10, 12, 14, 16, 18], results.sort
  end

  def test_continues_after_worker_exception
    results = []
    worker = proc do |work|
      raise StandardError, "expected rescued boom" if work == 5
      work * 2
    end
    pool = RactorPool.new(worker: worker, strategy: strategy, on_error: proc {}, name: self.class.name) { |result| results << result }

    10.times { |index| pool << index }
    pool.shutdown

    assert_equal 9, results.size
    assert_equal [0, 2, 4, 6, 8, 12, 14, 16, 18], results.sort
  end

  def test_warns_by_default_when_worker_raises
    results = []
    worker = proc do |work|
      raise StandardError, "expected boom" if work == 5
      work * 2
    end

    _stdout, stderr = capture_io do
      pool = RactorPool.new(worker: worker, strategy: strategy, name: self.class.name) { |result| results << result }
      10.times { |index| pool << index }
      pool.shutdown
    end

    assert_equal 9, results.size
    assert_equal [0, 2, 4, 6, 8, 12, 14, 16, 18], results.sort
    assert_match "StandardError", stderr
  end

  def test_calls_on_error_when_worker_raises
    error_count = Atom.new(0)
    on_error = proc { error_count.swap { |count| count + 1 } }
    worker = proc do |work|
      raise StandardError, "expected boom" if work == 5
      work * 2
    end
    pool = RactorPool.new(worker: worker, strategy: strategy, on_error: on_error, name: self.class.name)

    10.times { |index| pool << index }
    pool.shutdown

    assert_equal 1, error_count.value
  end

  def test_handles_different_data_types
    results = []
    worker = ->(work) { work.class.name }
    pool = RactorPool.new(worker: worker, strategy: strategy, name: self.class.name) { |result| results << result }

    ["hello", :world, 1, {}].each { |work| pool << work }
    pool.shutdown

    assert_equal ["Hash", "Integer", "String", "Symbol"], results.sort
  end

  def test_raises_error_when_queueing_after_shutdown
    worker = ->(work) { work }
    pool = RactorPool.new(worker: worker, strategy: strategy, name: self.class.name)
    pool.shutdown

    error = assert_raises(RactorPool::EnqueuedWorkAfterShutdownError) do
      pool << 1
    end

    assert_equal "cannot queue work after shutdown", error.message
  end

  def test_shutdown_is_idempotent
    worker = ->(work) { work }
    pool = RactorPool.new(worker: worker, strategy: strategy, name: self.class.name)

    pool.shutdown
    pool.shutdown
    pool.shutdown
  end
end

class TestRactorPoolCoordinator < Minitest::Test
  include RactorPoolStrategyTests

  def strategy = :coordinator

  def expected_default_ractor_count = 1 + 1 + Etc.nprocessors # main ractor, coordinator ractor, worker ractors
  def expected_size_two_ractor_count = 1 + 1 + 2 # main ractor, coordinator ractor, worker ractors
end

class TestRactorPoolRoundRobin < Minitest::Test
  include RactorPoolStrategyTests

  def strategy = :round_robin

  def expected_default_ractor_count = 1 + Etc.nprocessors # main ractor, worker ractors
  def expected_size_two_ractor_count = 1 + 2 # main ractor, worker ractors

  def test_distributes_work_evenly
    results = []
    worker = proc { |_work| Ractor.current.name }
    pool = RactorPool.new(size: 4, worker: worker, strategy: strategy, name: self.class.name) { |name| results << name }

    16.times { |index| pool << index }
    pool.shutdown

    counts_by_worker = results.tally
    assert_equal 4, counts_by_worker.size
    assert_equal [4, 4, 4, 4], counts_by_worker.values
  end
end
