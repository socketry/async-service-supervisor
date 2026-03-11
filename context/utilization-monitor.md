# Utilization Monitor

This guide explains how to use the {ruby Async::Service::Supervisor::UtilizationMonitor} to collect and aggregate application-level utilization metrics from your worker processes.

## Overview

While the {ruby Async::Service::Supervisor::ProcessMonitor} captures OS-level metrics (CPU, memory) and the {ruby Async::Service::Supervisor::MemoryMonitor} takes action when limits are exceeded, the `UtilizationMonitor` focuses on **application-level metrics**—connections, requests, queue depths, and other business-specific utilization data. Without it, you can't easily answer questions like "How many active connections do my workers have?" or "What is the total request throughput across all workers?"

The `UtilizationMonitor` solves this by using shared memory to efficiently collect metrics from workers and aggregate them by service name. Workers write metrics to a shared memory segment; the supervisor periodically reads and aggregates them without any IPC overhead during collection.

Use the `UtilizationMonitor` when you need:

- **Application observability**: Track connections, requests, queue depths, or custom metrics across workers.
- **Service-level aggregation**: See totals per service (e.g., "echo" service: 42 connections, 1000 messages).
- **Lightweight collection**: Avoid IPC or network calls—metrics are read directly from shared memory.
- **Integration with logging**: Emit aggregated metrics to your logging pipeline for dashboards and alerts.

The monitor uses the `async-utilization` gem for schema definition and shared memory layout. Workers must include {ruby Async::Service::Supervisor::Supervised} and define a `utilization_schema` to participate.

## Usage

### Supervisor Configuration

Add a utilization monitor to your supervisor service:

```ruby
service "supervisor" do
	include Async::Service::Supervisor::Environment
	
	monitors do
		[
			Async::Service::Supervisor::UtilizationMonitor.new(
				path: File.expand_path("utilization.shm", root),
				interval: 10 # Aggregate and emit metrics every 10 seconds
			)
		]
	end
end
```

### Worker Configuration

Workers must include {ruby Async::Service::Supervisor::Supervised} and define a `utilization_schema` that describes the metrics they expose:

```ruby
service "echo" do
	include Async::Service::Managed::Environment
	include Async::Service::Supervisor::Supervised
	
	service_class EchoService
	
	utilization_schema do
		{
			connections_total: :u64,
			connections_active: :u32,
			messages_total: :u64
		}
	end
end
```

### Emitting Metrics from Workers

Workers obtain a utilization registry from the evaluator and use it to update metrics:

```ruby
def run(instance, evaluator)
	evaluator.prepare!(instance)
	instance.ready!
	
	registry = evaluator.utilization_registry
	connections_total = registry.metric(:connections_total)
	connections_active = registry.metric(:connections_active)
	messages_total = registry.metric(:messages_total)
	
	@bound_endpoint.accept do |peer|
		connections_total.increment
		connections_active.track do
			peer.each_line do |line|
				messages_total.increment
				peer.write(line)
			end
		end
	end
end
```

The supervisor aggregates these metrics by service name and emits them at the configured interval. For example:

```json
{
	"echo": {
		"connections_total": 150,
		"connections_active": 12,
		"messages_total": 45000
	}
}
```

## Configuration Options

### `path`

Path to the shared memory file used for worker metrics. Default: `"utilization.shm"` (relative to current working directory).

Be explicit about the path when using {ruby Async::Service::Supervisor::Environment} so supervisor and workers resolve the same file regardless of working directory:

```ruby
monitors do
	[
		Async::Service::Supervisor::UtilizationMonitor.new(
			path: File.expand_path("utilization.shm", root),
			interval: 10
		)
	]
end
```

### `interval`

The interval (in seconds) at which to aggregate and emit utilization metrics. Default: `10` seconds.

```ruby
# Emit every second for high-frequency monitoring
Async::Service::Supervisor::UtilizationMonitor.new(interval: 1)

# Emit every 5 minutes for low-overhead monitoring
Async::Service::Supervisor::UtilizationMonitor.new(interval: 300)
```

### `size`

Total size of the shared memory buffer. Default: `IO::Buffer::PAGE_SIZE * 8`. The buffer grows automatically when more workers are registered than segments available.

```ruby
Async::Service::Supervisor::UtilizationMonitor.new(
	size: IO::Buffer::PAGE_SIZE * 32  # Larger initial buffer for many workers
)
```

### `segment_size`

Size of each allocation segment per worker. Default: `512` bytes. Must accommodate your schema; the `async-utilization` gem lays out fields according to type (e.g., `u64` = 8 bytes, `u32` = 4 bytes).

```ruby
Async::Service::Supervisor::UtilizationMonitor.new(
	segment_size: 256  # Smaller segments if schema is compact
)
```

## Schema Types

The `utilization_schema` maps metric names to types supported by {ruby IO::Buffer}:

| Type | Size | Use case |
|------|------|----------|
| `:u32` | 4 bytes | Counters that may wrap (e.g., connections_active) |
| `:u64` | 8 bytes | Monotonically increasing counters (e.g., requests_total) |
| `:i32` | 4 bytes | Signed 32-bit values |
| `:i64` | 8 bytes | Signed 64-bit values |
| `:f32` | 4 bytes | Single-precision floats |
| `:f64` | 8 bytes | Double-precision floats |

Prefer `:u64` for totals that only increase; use `:u32` for gauges or values that may decrease.

## Default Schema

The {ruby Async::Service::Supervisor::Supervised} mixin provides a default schema if you don't override `utilization_schema`:

```ruby
{
	connections_active: :u32,
	connections_total: :u64,
	requests_active: :u32,
	requests_total: :u64
}
```

Override it when your service has different metrics:

```ruby
utilization_schema do
	{
		connections_active: :u32,
		connections_total: :u64,
		messages_total: :u64,
		queue_depth: :u32
	}
end
```

## Metric API

The utilization registry provides methods to update metrics:

- **`increment`**: Increment a counter by 1.
- **`set(value)`**: Set a gauge to a specific value.
- **`track { ... }`**: Execute a block and increment/decrement a gauge around it (e.g., `connections_active` while handling a connection).

```ruby
connections_total = registry.metric(:connections_total)
connections_active = registry.metric(:connections_active)

# Increment total connections when a client connects
connections_total.increment

# Track active connections for the duration of the block
connections_active.track do
	handle_client(peer)
end
```

## Aggregation Behavior

Metrics are aggregated by service name (from `supervisor_worker_state[:name]`). Values are summed across workers of the same service. For example, with 4 workers each reporting `connections_active: 3`, the aggregated value is `12`.

## Best Practices

- **Define a minimal schema**: Only include metrics you need; each field consumes shared memory.
- **Use appropriate types**: `u64` for ever-increasing counters; `u32` for gauges.
- **Match schema across workers**: All workers of the same service should use the same schema for consistent aggregation.
- **Combine with other monitors**: Use `UtilizationMonitor` alongside `ProcessMonitor` and `MemoryMonitor` for full observability.

## Common Pitfalls

- **Workers without schema**: Workers that don't define `utilization_schema` (or return `nil`) are not registered. They won't contribute to utilization metrics.
- **Schema mismatch**: If workers of the same service use different schemas, aggregation may produce incorrect or partial results.
- **Path permissions**: Ensure the shared memory path is accessible to all worker processes (e.g., same user, or appropriate permissions).
- **Segment size**: If your schema is large, increase `segment_size` to avoid allocation failures.
