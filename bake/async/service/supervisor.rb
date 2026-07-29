# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

def initialize(...)
	super
	
	require "async/service/supervisor"
end

# Restart the container, typically causing it to exit (the parent process should then restart it).
def restart
	client do |connection|
		supervisor = connection[:supervisor]
		supervisor.restart
	end
end

# Reload the services gracefully, allowing them to reconfigure without dropping connections.
def reload
	client do |connection|
		supervisor = connection[:supervisor]
		supervisor.restart(signal: :HUP)
	end
end

def status
	client do |connection|
		supervisor = connection[:supervisor]
		supervisor.status
	end
end

# List the connection IDs of all registered workers.
def workers
	client do |connection|
		supervisor = connection[:supervisor]
		supervisor.keys
	end
end

# Dump the object space of a worker to a file on the worker's filesystem.
#
# @parameter connection_id [Integer] The connection ID of the worker to target.
# @parameter path [String] The file path where the worker should write the dump.
def memory_dump(connection_id:, path:)
	with_worker(connection_id) do |worker|
		worker.memory_dump(path: path)
	end
end

# Dump the fiber scheduler hierarchy of a worker.
#
# @parameter connection_id [Integer] The connection ID of the worker to target.
# @parameter path [String | Nil] An optional file path on the worker's filesystem.
# @parameter log [String | Nil] An optional message to log with the dump.
def scheduler_dump(connection_id:, path: nil, log: nil)
	with_worker(connection_id) do |worker|
		worker.scheduler_dump(path: path, log: log)
	end
end

# Dump information about all threads in a worker.
#
# @parameter connection_id [Integer] The connection ID of the worker to target.
# @parameter path [String | Nil] An optional file path on the worker's filesystem.
def thread_dump(connection_id:, path: nil)
	with_worker(connection_id) do |worker|
		worker.thread_dump(path: path)
	end
end

# Start garbage collection profiling in a worker.
#
# @parameter connection_id [Integer] The connection ID of the worker to target.
def garbage_profile_start(connection_id:)
	with_worker(connection_id) do |worker|
		worker.garbage_profile_start
	end
end

# Stop garbage collection profiling in a worker and return or save the results.
#
# @parameter connection_id [Integer] The connection ID of the worker to target.
# @parameter path [String | Nil] An optional file path on the worker's filesystem.
def garbage_profile_stop(connection_id:, path: nil)
	with_worker(connection_id) do |worker|
		worker.garbage_profile_stop(path: path)
	end
end

private

def endpoint
	Async::Service::Supervisor.endpoint
end

def with_worker(connection_id)
	client do |connection|
		supervisor = connection[:supervisor]
		yield supervisor[connection_id]
	end
end

def client(&block)
	Sync do
		Async::Service::Supervisor::Client.new(endpoint: self.endpoint).connect(&block)
	end
end
