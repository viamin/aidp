# Concurrency Patterns

This document describes the concurrency patterns and synchronization primitives used in AIDP.

## Why Not `sleep`?

Arbitrary `sleep()` calls in production code are **anti-patterns** because they:

1. **Hide race conditions** - Timing-based waits mask underlying synchronization issues
2. **Create flaky tests** - Tests that rely on timing can fail unpredictably
3. **Waste resources** - Blocked threads consume memory while doing nothing
4. **Reduce throughput** - Fixed delays are often longer than necessary
5. **Make code untestable** - Hard to override sleep duration in tests

## Approved Patterns

AIDP uses `concurrent-ruby` for all concurrency needs, with standardized helpers in the `Aidp::Concurrency` module.

### Pattern 1: Waiting for Conditions

**Don't do this:**

```ruby
sleep 1 until File.exist?(path)
```

**Do this instead:**

```ruby
require "aidp/concurrency"

Aidp::Concurrency::Wait.until(timeout: 30, interval: 0.2) do
  File.exist?(path)
end
```

**Why:** Deterministic timeout enforcement, early exit on success, and proper logging.

**Common use cases:**

- Waiting for files to appear
- Waiting for ports to open
- Waiting for processes to exit
- Polling external state

**Helpers available:**

```ruby
# Generic condition wait
Wait.until(timeout: 30, interval: 0.2) { condition? }

# Specialized helpers
Wait.for_file(path, timeout: 30)
Wait.for_port("localhost", 8080, timeout: 60)
Wait.for_process_exit(pid, timeout: 30)
```

### Pattern 2: Retry with Backoff

**Don't do this:**

```ruby
retries = 0
begin
  call_external_api
rescue Net::ReadTimeout
  retries += 1
  raise if retries > 5
  sleep 2 ** retries
  retry
end
```

**Do this instead:**

```ruby
require "aidp/concurrency"

Aidp::Concurrency::Backoff.retry(
  max_attempts: 5,
  base: 0.5,
  jitter: 0.2,
  on: [Net::ReadTimeout, Errno::ECONNREFUSED]
) do
  call_external_api
end
```

**Why:** Standardized backoff strategies (exponential, linear, constant), jitter to prevent thundering herd, automatic logging.

**Options:**

```ruby
Backoff.retry(
  max_attempts: 5,        # Maximum retry attempts
  base: 0.5,              # Base delay in seconds
  max_delay: 30.0,        # Maximum delay cap
  jitter: 0.2,            # Jitter factor (0.0-1.0)
  strategy: :exponential, # :exponential, :linear, or :constant
  on: [StandardError]     # Exception classes to retry
) { risky_operation }
```

**Strategies:**

- **Exponential**: `delay = base * 2^(attempt-1)` - best for temporary failures
- **Linear**: `delay = base * attempt` - predictable backoff
- **Constant**: `delay = base` - simple fixed delays

### Pattern 3: Async Execution & Thread Pools

**Don't do this:**

```ruby
require "async"

Async do
  result = fetch_data
  process(result)
end
```

**Do this instead:**

```ruby
require "aidp/concurrency"

# Single future
future = Aidp::Concurrency::Exec.future { fetch_data }
result = future.value!  # Block until complete

# Multiple parallel futures
futures = [
  Exec.future { task1 },
  Exec.future { task2 },
  Exec.future { task3 }
]
results = Exec.zip(*futures).value!  # Wait for all
```

**Why:** Proper thread pool management, no fiber scheduler required, better error handling.

**Named executors:**

```ruby
# Use named pools for different workload types
io_pool = Exec.pool(name: :io_pool, size: 20)      # I/O-bound
cpu_pool = Exec.pool(name: :cpu_pool, size: 4)     # CPU-bound
bg_pool = Exec.pool(name: :background, size: 5)    # Background tasks

# Execute on specific pool
future = Concurrent::Promises.future_on(io_pool) { fetch_remote_data }
```

### Pattern 4: Periodic Tasks

**Don't do this:**

```ruby
loop do
  perform_task
  sleep 60
end
```

**Do this instead:**

```ruby
require "concurrent-ruby"

task = Concurrent::TimerTask.new(execution_interval: 60) do
  perform_task
end
task.execute

# Later...
task.shutdown
```

**Why:** Proper cancellation support, exception handling, and resource cleanup.

**Advanced periodic tasks:**

```ruby
task = Concurrent::TimerTask.new(
  execution_interval: 60,
  timeout_interval: 300,
  run_now: true
) do |task|
  begin
    perform_work
  rescue => e
    Aidp.logger.error("periodic_task", "Task failed: #{e.message}")
    raise  # Stop task on error
  end
end

task.add_observer do |time, result, ex|
  if ex
    Aidp.logger.error("task_observer", "Task exception: #{ex}")
  end
end

task.execute
```

## Configuration

Configure global defaults in an initializer or config file:

```ruby
Aidp::Concurrency.configure do |config|
  config.default_timeout = 30.0
  config.default_interval = 0.2
  config.default_max_attempts = 5
  config.default_backoff_base = 0.5
  config.default_backoff_max = 30.0
  config.default_jitter = 0.2
  config.log_long_waits_threshold = 5.0
  config.log_retries = true
end

# Set custom logger
Aidp::Concurrency.logger = Aidp.logger
```

## Migration Guide

### From `sleep` to `Wait.until`

**Before:**

```ruby
sleep 0.1 until ready?
```

**After:**

```ruby
Wait.until(timeout: 30, interval: 0.1) { ready? }
```

### From `Async::Task.current.sleep` to Regular Sleep

Most conditional async sleep can be replaced with regular `sleep` in non-async contexts:

**Before:**

```ruby
if Async::Task.current?
  Async::Task.current.sleep(delay)
else
  sleep(delay)
end
```

**After (if inside Backoff.retry):**

```ruby
# No sleep needed - Backoff.retry handles it
Backoff.retry(base: delay) { operation }
```

**After (if genuinely needed):**

```ruby
sleep(delay)  # Prefer Wait.until with actual condition
```

### From Manual Retry to `Backoff.retry`

**Before:**

```ruby
attempt = 0
begin
  risky_call
rescue SomeError
  attempt += 1
  raise if attempt > 3
  sleep(2 ** attempt)
  retry
end
```

**After:**

```ruby
Backoff.retry(max_attempts: 3, on: [SomeError]) { risky_call }
```

### From `Async do` to `Exec.future`

**Before:**

```ruby
require "async"

Async do |task|
  result = expensive_work
  callback(result)
end
```

**After:**

```ruby
future = Exec.future { expensive_work }
future.then { |result| callback(result) }
    .rescue { |error| handle_error(error) }
```

## Testing Patterns

### Testing with Timeouts

Use shorter timeouts in tests, but long enough to avoid flakiness:

```ruby
RSpec.describe "MyFeature" do
  around do |example|
    Aidp::Concurrency.configure do |c|
      c.default_timeout = 5.0  # Faster tests
      c.default_interval = 0.05
    end
    example.run
  end

  it "waits for condition" do
    start_async_operation
    Wait.until(timeout: 2) { operation_complete? }
    expect(result).to eq(expected)
  end
end
```

### Testing Retry Logic

```ruby
it "retries on failure" do
  attempt = 0
  result = Backoff.retry(max_attempts: 3, base: 0.01) do
    attempt += 1
    raise "fail" if attempt < 3
    "success"
  end

  expect(attempt).to eq(3)
  expect(result).to eq("success")
end
```

## Advanced Patterns

### Combining Futures with Waits

```ruby
# Start background work
future = Exec.future { long_running_task }

# Wait for a side effect with timeout
Wait.until(timeout: 60) { File.exist?("/tmp/ready") }

# Then get the result
result = future.value!
```

### Circuit Breaker Pattern

```ruby
class CircuitBreaker
  def initialize(threshold: 5, timeout: 60)
    @failure_count = Concurrent::AtomicFixnum.new(0)
    @threshold = threshold
    @timeout = timeout
    @open_until = Concurrent::AtomicReference.new(nil)
  end

  def call(&block)
    if open?
      raise "Circuit breaker open"
    end

    Backoff.retry(max_attempts: 3, on: [StandardError]) do
      result = block.call
      reset
      result
    end
  rescue => e
    trip
    raise
  end

  private

  def open?
    if deadline = @open_until.get
      if Time.now < deadline
        return true
      else
        reset
      end
    end
    false
  end

  def trip
    if @failure_count.increment >= @threshold
      @open_until.set(Time.now + @timeout)
    end
  end

  def reset
    @failure_count.value = 0
    @open_until.set(nil)
  end
end
```

### Rate Limiting

```ruby
require "concurrent-ruby"

class RateLimiter
  def initialize(max_requests:, period:)
    @semaphore = Concurrent::Semaphore.new(max_requests)
    @period = period
  end

  def call(&block)
    @semaphore.acquire
    Thread.new do
      sleep @period
      @semaphore.release
    end
    block.call
  end
end
```

## Common Pitfalls

### 1. Don't Use Sleep in Tight Loops

```ruby
# Bad
loop do
  break if ready?
  sleep 0.01
end

# Good
Wait.until(timeout: 30, interval: 0.1) { ready? }
```

### 2. Don't Ignore Timeouts

```ruby
# Bad - could hang forever
Wait.until(timeout: Float::INFINITY) { condition }

# Good - always have a reasonable timeout
Wait.until(timeout: 60) { condition }
```

### 3. Don't Over-Parallelize

```ruby
# Bad - could exhaust resources
1000.times.map { Exec.future { work } }

# Good - use bounded concurrency
pool = Exec.pool(name: :limited, size: 10)
1000.times.map { Concurrent::Promises.future_on(pool) { work } }
```

## Resources

- [concurrent-ruby documentation](https://github.com/ruby-concurrency/concurrent-ruby)
- [Ruby concurrency guide](https://ruby-doc.org/core/Thread.html)
- [Issue #153: Audit & Replace sleep](https://github.com/viamin/aidp/issues/153)

## Summary

**Golden Rules:**

1. ✅ Use `Wait.until` for condition polling
2. ✅ Use `Backoff.retry` for retry logic
3. ✅ Use `Exec.future` for async execution
4. ✅ Use `TimerTask` for periodic work
5. ✅ Always specify timeouts
6. ✅ Use jitter in backoff to prevent thundering herd
7. ❌ Never use arbitrary `sleep()` in production code
8. ❌ Never use `Async::Task.current.sleep`
9. ❌ Never wait without a maximum timeout
