# Memory Monitor

This guide explains how to use the {ruby Async::Service::Supervisor::MemoryMonitor} to detect and restart workers that exceed memory limits or develop memory leaks.

## Overview

Long-running worker processes often accumulate memory over time, either through legitimate growth or memory leaks. Without intervention, workers can consume all available system memory, causing performance degradation or system crashes. The `MemoryMonitor` solves this by automatically detecting and restarting problematic workers before they impact system stability.

Use the `MemoryMonitor` when you need:

- **Memory leak protection**: Automatically restart workers that continuously accumulate memory.
- **Resource limits**: Enforce maximum memory usage per worker.
- **System stability**: Prevent runaway processes from exhausting system memory.
The monitor uses the `memory-leak` gem to track process memory usage over time, detecting abnormal growth patterns that indicate leaks.

## Usage

Add a memory monitor to your supervisor service to automatically restart workers that exceed 500MB:

```ruby
service "supervisor" do
	include Async::Service::Supervisor::Environment
	
	monitors do
		[
			Async::Service::Supervisor::MemoryMonitor.new(
				# Check worker memory every 10 seconds:
				interval: 10,
				
				# Restart workers exceeding 500MB:
				maximum_size_limit: 1024 * 1024 * 500
			)
		]
	end
end
```

When a worker exceeds the limit, the monitor uses a two-phase response:

1. **First check**: Invokes a major garbage collection in the worker via RPC (`WorkerController#garbage_collect`), giving it a chance to reclaim memory.
2. **Next check**: If still exceeding → sends `SIGINT` to gracefully shut down the worker. If recovered → logs and continues monitoring.
3. The container automatically spawns a replacement worker when one is killed.

No worker opt-in is required—workers already have `WorkerController` with `garbage_collect`. If the worker has no RPC connection (e.g. not yet registered), the monitor kills immediately.

## Configuration Options

The `MemoryMonitor` accepts the following options:

### `interval`

The interval (in seconds) at which to check for memory leaks. Default: `10` seconds.

```ruby
Async::Service::Supervisor::MemoryMonitor.new(interval: 30)
```

### `maximum_size_limit`

The maximum memory size (in bytes) per process. When a process exceeds this limit, it will be restarted.

```ruby
# 500MB limit
Async::Service::Supervisor::MemoryMonitor.new(maximum_size_limit: 1024 * 1024 * 500)

# 1GB limit
Async::Service::Supervisor::MemoryMonitor.new(maximum_size_limit: 1024 * 1024 * 1024)
```

### `total_size_limit`

The total size limit (in bytes) for all monitored processes combined. If not specified, only per-process limits are enforced.

```ruby
# Total limit of 2GB across all workers
Async::Service::Supervisor::MemoryMonitor.new(
	maximum_size_limit: 1024 * 1024 * 500,  # 500MB per process
	total_size_limit: 1024 * 1024 * 1024 * 2  # 2GB total
)
```

## Memory Leak Detection

When a memory leak is detected, the monitor will:

1. Invoke a major garbage collection in the worker via RPC (if the worker is registered).
2. On the next check: if still exceeding, send `SIGINT` to gracefully restart the worker; if recovered, log and continue.
3. The container automatically restarts the worker process when one is killed.
