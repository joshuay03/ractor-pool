# rbs_inline: enabled
# frozen_string_literal: true

require "warning"
require "atomic-ruby/atom"

Warning.ignore(/Ractor API is experimental/, __FILE__)

# A thread-safe, lock-free pool of Ractor workers with a coordinator pattern for distributing work.
#
# RactorPool manages a fixed number of worker ractors that process work items in parallel.
# Work is distributed on-demand to idle workers, ensuring efficient utilisation. Results
# are collected and passed to a result handler running in a separate thread.
#
# @example Basic usage
#   results = []
#   worker = -> (work) { work * 2 }
#   pool = RactorPool.new(size: 4, worker: worker) { |result| results << result }
#
#   10.times { |index| pool << index }
#   pool.shutdown
#
#   p results #=> [2, 0, 6, 4, 14, 10, 8, 16, 18, 12]
#
# @example Without result handler
#   counter = Atom.new(0)
#   worker = proc do |work|
#     counter.swap { |current_value| current_value + 1 }
#     work * 2
#   end
#   pool = RactorPool.new(size: 4, worker: worker)
#
#   10.times { |index| pool << index }
#   pool.shutdown
#
#   p counter.value #=> 10
#
# @see https://docs.ruby-lang.org/en/master/language/ractor_md.html Ractor Guide
# @see https://docs.ruby-lang.org/en/master/Ractor.html Ractor API
# @see https://docs.ruby-lang.org/en/master/Ractor/Port.html Ractor::Port API
# @see https://github.com/joshuay03/atomic-ruby atomic-ruby gem
#
class RactorPool
  class Error < StandardError; end

  class EnqueuedWorkAfterShutdownError < Error
    # @rbs () -> String
    def message = "cannot queue work after shutdown"
  end

  SHUTDOWN = :shutdown
  private_constant :SHUTDOWN

  # @rbs @size: Integer
  # @rbs @worker: ^(untyped) -> untyped
  # @rbs @name: String?
  # @rbs @on_error: (^(Exception) -> void | nil)
  # @rbs @result_handler: (^(untyped) -> void | nil)
  # @rbs @in_flight: Atom[Integer]
  # @rbs @shutdown: Atom[bool]
  # @rbs @result_port: Ractor::Port?
  # @rbs @error_port: Ractor::Port?
  # @rbs @coordinator: Ractor?
  # @rbs @workers: Array[Ractor]
  # @rbs @collector: Thread?
  # @rbs @error_collector: Thread?

  # Creates a new RactorPool with the specified number of workers.
  #
  # @param size [Integer] number of worker ractors to create
  # @param worker [Proc] a shareable proc that processes each work item
  # @param name [String, nil] optional name for the pool, used in thread/ractor names
  # @param on_error [Proc, nil] optional shareable proc called with the raised exception when a worker raises
  # @yieldparam result [Object] the result returned by the worker proc
  # @return [void]
  # @raise [ArgumentError] if size is not a positive integer
  # @raise [ArgumentError] if worker is not a proc
  # @raise [ArgumentError] if on_error is given but is not a proc
  #
  # @example With result handler
  #   pool = RactorPool.new(size: 4, worker: proc { it }) { |result| puts result }
  #
  # @example Without result handler
  #   pool = RactorPool.new(size: 4, worker: proc { it })
  #
  # @example With error handler
  #   error_count = Atom.new(0)
  #   on_error = proc { error_count.swap { |count| count + 1 } }
  #   pool = RactorPool.new(size: 4, worker: proc { raise }, on_error: on_error)
  #
  # @rbs (?size: Integer, worker: ^(untyped) -> untyped, ?name: String?, ?on_error: (^(Exception) -> void | nil)) ?{ (untyped) -> void } -> void
  def initialize(size: Etc.nprocessors, worker:, name: nil, on_error: nil, &result_handler)
    raise ArgumentError, "size must be a positive Integer" unless size.is_a?(Integer) && size > 0
    raise ArgumentError, "worker must be a Proc" unless worker.is_a?(Proc)
    raise ArgumentError, "on_error must be a Proc" if on_error && !on_error.is_a?(Proc)

    @size = size
    @worker = Ractor.shareable_proc(&worker)
    @name = name
    @on_error = Ractor.shareable_proc(&on_error) if on_error
    @result_handler = result_handler

    @in_flight = Atom.new(0)
    @shutdown  = Atom.new(false)

    @result_port = Ractor::Port.new if result_handler
    @error_port  = Ractor::Port.new unless on_error
    @coordinator = start_coordinator if size > 1
    @workers = start_workers
    @collector = start_collector
    @error_collector = start_error_collector
  end

  # Queues a work item to be processed by an available worker.
  #
  # @param work [Object] the work item to process
  # @return [void]
  # @raise [EnqueuedWorkAfterShutdownError] if the pool has been shut down
  #
  # @example
  #   pool << "http://example.com/page1"
  #   pool << "http://example.com/page2"
  #
  # @rbs (untyped work) -> void
  def <<(work)
    raise EnqueuedWorkAfterShutdownError if @shutdown.value

    @in_flight.swap { |count| count + 1 }

    if @shutdown.value
      @in_flight.swap { |count| count - 1 }
      raise EnqueuedWorkAfterShutdownError
    end

    begin
      (@coordinator || @workers.first).send(work, move: true)
    ensure
      @in_flight.swap { |count| count - 1 }
    end
  end

  # Shuts down the pool gracefully.
  #
  # This method:
  # 1. Prevents new work from being queued
  # 2. Waits for all in-flight work submissions to complete
  # 3. Allows all queued work to complete
  # 4. Waits for all workers to finish
  # 5. Waits for all results and errors to be processed
  #
  # This method is idempotent and can be called multiple times safely.
  #
  # @return [void]
  #
  # @example
  #   pool.shutdown
  #
  # @rbs () -> void
  def shutdown
    already_shutdown = false
    @shutdown.swap do |current|
      if current
        already_shutdown = true
        current
      else
        true
      end
    end
    return if already_shutdown

    Thread.pass until @in_flight.value.zero?

    @coordinator&.send(SHUTDOWN, move: true) ||
      (@workers.first.send(SHUTDOWN, move: true) && @result_port&.send(SHUTDOWN, move: true))
    @workers.each(&:join)
    @coordinator&.join
    @error_port&.send(SHUTDOWN, move: true)
    @error_collector&.join
    @collector&.join
  end

  private

  # @rbs () -> Ractor
  def start_coordinator
    ractor_name = String.new("#{self.class.name} coordinator ractor")
    ractor_name << " for #{@name}" if @name

    Ractor.new(@size, @result_port, name: ractor_name) do |worker_count, result_port|
      work_queue = []
      waiting_workers = []
      shutdown_received = false
      workers_finished = 0

      loop do
        case data = Ractor.receive
        when SHUTDOWN
          shutdown_received = true

          workers_finished += waiting_workers.size
          waiting_workers.each { |worker| worker.send(SHUTDOWN, move: true) }
          waiting_workers.clear
          if workers_finished == worker_count
            result_port&.send(SHUTDOWN, move: true)
            break
          end

        when Ractor
          ractor = data

          if work_queue.any?
            ractor.send(work_queue.shift, move: true)
          elsif shutdown_received
            ractor.send(SHUTDOWN, move: true)

            workers_finished += 1
            if workers_finished == worker_count
              result_port&.send(SHUTDOWN, move: true)
              break
            end
          else
            waiting_workers << ractor
          end

        else
          work = data

          if waiting_workers.any?
            waiting_workers.shift.send(work, move: true)
          else
            work_queue << work
          end
        end
      end
    end
  end

  # @rbs () -> Array[Ractor]
  def start_workers
    @size.times.map do |index|
      ractor_name = String.new("#{self.class.name} ractor #{index}")
      ractor_name << " for #{@name}" if @name

      Ractor.new(@worker, @on_error, @error_port, @coordinator, @result_port, name: ractor_name) do |worker, on_error, error_port, coordinator, result_port|
        loop do
          coordinator&.send(Ractor.current, move: true)

          work = Ractor.receive
          break if work == SHUTDOWN

          begin
            result = worker.call(work)

            result_port&.send(result, move: true)
          rescue => error
            on_error ? on_error.call(error) : error_port.send(error.full_message, move: true)
          end
        end
      end
    end
  end

  # @rbs () -> Thread?
  def start_collector
    return unless @result_handler

    thread_name = String.new("#{self.class.name} collector thread")
    thread_name << " for #{@name}" if @name

    Thread.new(@result_port, @result_handler, thread_name) do |result_port, result_handler, name|
      Thread.current.name = name

      loop do
        result = result_port.receive
        break if result == SHUTDOWN

        result_handler.call(result)
      end
    end
  end

  # @rbs () -> Thread?
  def start_error_collector
    return if @on_error

    thread_name = String.new("#{self.class.name} error collector thread")
    thread_name << " for #{@name}" if @name

    Thread.new(@error_port, thread_name) do |error_port, name|
      Thread.current.name = name

      loop do
        message = error_port.receive
        break if message == SHUTDOWN

        warn message
      end
    end
  end
end
