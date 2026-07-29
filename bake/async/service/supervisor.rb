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
	client do |connection|
		supervisor = connection[:supervisor]
		worker = supervisor[connection_id]
		worker.memory_dump(path: path)
	end
end

private

def endpoint
	Async::Service::Supervisor.endpoint
end

def client(&block)
	Sync do
		Async::Service::Supervisor::Client.new(endpoint: self.endpoint).connect(&block)
	end
end
