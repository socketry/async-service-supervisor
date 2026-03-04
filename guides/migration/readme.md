# Migration Guide

This guide explains how to migrate from `async-container-supervisor` to `async-service-supervisor`. The new version provides a cleaner API built on `Async::Bus` for improved reliability and maintainability.

## Overview

`async-service-supervisor` is the successor to `async-container-supervisor`, providing the same process supervision capabilities with an improved architecture. The main changes include:

- **Namespace migration**: `Async::Container::Supervisor` → `Async::Service::Supervisor`.
- **Simplified worker connection API**: New `prepare!` method replaces manual worker creation.
- **Bus-based communication**: Uses `Async::Bus` for more reliable IPC.
- **Improved environment integration**: Better integration with `Async::Service::Managed::Environment`.

## Why Migrate?

The new version provides several benefits:

- **Better reliability**: Built on `Async::Bus` which provides more robust communication patterns.
- **Simpler API**: Less boilerplate code required for worker setup.
- **Better integration**: Improved integration with the `async-service` ecosystem.
- **Future-proof**: Aligned with the direction of the async-service framework.

## Step-by-Step Migration

### 1. Update Gem Dependency

Update your `Gemfile` or `gems.rb`:

```ruby
# Before:
gem "async-container-supervisor"

# After:
gem "async-service-supervisor"
```

Then run:

```bash
$ bundle install
```

### 2. Update Require Statements

Update all require statements in your code:

```ruby
# Before:
require "async/container/supervisor"

# After:
require "async/service/supervisor"
```

### 3. Update Namespace References

Replace all references to `Async::Container::Supervisor` with `Async::Service::Supervisor`:

```ruby
# Before:
include Async::Container::Supervisor::Environment
include Async::Container::Supervisor::Supervised

Async::Container::Supervisor::MemoryMonitor.new(...)
Async::Container::Supervisor::ProcessMonitor.new(...)

# After:
include Async::Service::Supervisor::Environment
include Async::Service::Supervisor::Supervised

Async::Service::Supervisor::MemoryMonitor.new(...)
Async::Service::Supervisor::ProcessMonitor.new(...)
```

### 4. Update Worker Service Setup

The worker connection API has been simplified. Update your worker service implementation:

**Before (`async-container-supervisor`):**

```ruby
class MyWorkerService < Async::Service::Generic
	def setup(container)
		super
		
		container.run(name: self.class.name, count: 4, restart: true) do |instance|
			Async do
				# Connect to the supervisor if available:
				if @environment.implements?(Async::Container::Supervisor::Supervised)
					@evaluator.make_supervised_worker(instance).run
				end
				
				# Mark the worker as ready:
				instance.ready!
				
				# Your worker logic here:
				loop do
					# Do work...
					sleep 1
					instance.ready!
				end
			end
		end
	end
end
```

**After (`async-service-supervisor`):**

```ruby
class MyWorkerService < Async::Service::Generic
	def setup(container)
		super
		
		container.run(name: self.class.name, count: 4, restart: true) do |instance|
			Async do
				# Get the environment evaluator:
				evaluator = self.environment.evaluator
				
				# Prepare the instance (connects to supervisor if available):
				evaluator.prepare!(instance)
				
				# Mark the worker as ready:
				instance.ready!
				
				# Your worker logic here:
				loop do
					# Do work...
					sleep 1
					instance.ready!
				end
			end
		end
	end
end
```

**Key changes:**
- Removed the `implements?` check - `prepare!` handles this automatically.
- Use `evaluator.prepare!(instance)` instead of `@evaluator.make_supervised_worker(instance).run`.
- The `prepare!` method calls `super(instance)` first (which may invoke parent module implementations), then connects to the supervisor by calling `supervisor_worker.run`.

### 5. Update Service Configuration

Update your service configuration blocks:

```ruby
# Before:
service "worker" do
	service_class MyWorkerService
	include Async::Container::Supervisor::Supervised
end

service "supervisor" do
	include Async::Container::Supervisor::Environment
end

# After:
service "worker" do
	service_class MyWorkerService
	include Async::Service::Supervisor::Supervised
end

service "supervisor" do
	include Async::Service::Supervisor::Environment
end
```

### 6. Update Monitor Configuration

Monitor configuration remains the same, but update the class names:

```ruby
# Before:
service "supervisor" do
	include Async::Container::Supervisor::Environment
	
	monitors do
		[
			Async::Container::Supervisor::ProcessMonitor.new(interval: 60),
			Async::Container::Supervisor::MemoryMonitor.new(
				interval: 10,
				maximum_size_limit: 1024 * 1024 * 500
			)
		]
	end
end

# After:
service "supervisor" do
	include Async::Service::Supervisor::Environment
	
	monitors do
		[
			Async::Service::Supervisor::ProcessMonitor.new(interval: 60),
			Async::Service::Supervisor::MemoryMonitor.new(
				interval: 10,
				maximum_size_limit: 1024 * 1024 * 500
			)
		]
	end
end
```

### 7. Update Bake Tasks

If you're using bake tasks, update the namespace:

**Before:**

```bash
$ bake async:container:supervisor:restart
$ bake async:container:supervisor:reload
$ bake async:container:supervisor:status
$ bake async:container:supervisor:memory_sample duration=30 connection_id=...
```

**After:**

```bash
$ bake async:service:supervisor:restart
$ bake async:service:supervisor:reload
$ bake async:service:supervisor:status
```

**Note:** The `memory_sample` bake task has been removed in `async-service-supervisor`. This functionality was removed as it wasn't very useful and added complexity. If you were using memory sampling, you'll need to find alternative approaches for memory leak detection, such as using the `MemoryMonitor` with appropriate limits or external memory profiling tools.

### 8. Update Programmatic Client Usage

If you're using the supervisor client programmatically, update the API:

**Before (`async-container-supervisor`):**

```ruby
client = Async::Container::Supervisor::Client.new(endpoint: endpoint)
client.connect do |connection|
	# Direct call-based API:
	result = connection.call(do: :restart)
	result = connection.call(do: :status)
	result = connection.call(do: :forward, operation: {...}, connection_id: "...")
end
```

**After (`async-service-supervisor`):**

```ruby
client = Async::Service::Supervisor::Client.new(endpoint: endpoint)
client.connect do |connection|
	# Bus-based API with controller:
	supervisor = connection[:supervisor]
	supervisor.restart
	supervisor.status
	
	# Worker operations use the worker controller:
	worker = connection[:worker]
	# Worker operations are available through the worker controller
end
```

**Key changes:**
- Client now extends `Async::Bus::Client` instead of custom implementation.
- Access supervisor operations via `connection[:supervisor]` instead of `connection.call(do: :...)`.
- Worker operations are accessed through `connection[:worker]` controller.
- The `forward` operation (used for `memory_sample` and other worker operations) has been removed - use the worker controller API instead.

### 9. Update Environment Module Usage

The `Environment` module now includes `Async::Service::Managed::Environment` and has additional methods:

**New in `async-service-supervisor`:**

```ruby
service "supervisor" do
	include Async::Service::Supervisor::Environment
	
	# You can now override count if needed (defaults to 1):
	def count
		1  # Always 1 for supervisor
	end
	
	# container_options now merges with Managed::Environment defaults
end
```

The `container_options` method now properly merges with `Managed::Environment` defaults, providing better integration with the async-service framework.

## Architecture Changes

### Communication Protocol

The underlying communication protocol has changed from a custom protocol to `Async::Bus`:

- **Before**: Custom `Connection` class with `call(do: :...)` API.
- **After**: `Async::Bus` with controller-based API (`connection[:supervisor]`, `connection[:worker]`).

This provides:
- Better type safety through controller interfaces.
- More reliable message delivery.
- Better error handling and reconnection logic.

### Worker Registration

Worker registration has been refactored:

- **Before**: Workers passed state hash and received UUID connection IDs.
- **After**: Workers use `WorkerController` and receive sequential integer IDs.

The new approach provides:
- Simpler ID management.
- Better controller-based API.
- More explicit worker lifecycle management.
