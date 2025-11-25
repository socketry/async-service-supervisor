# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

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

# Sample memory allocations from a worker over a time period.
#
# This is useful for identifying memory leaks by tracking allocations
# that are retained after garbage collection.
#
# @parameter duration [Integer] The duration in seconds to sample for (default: 10).
# @parameter connection_id [Integer] The connection ID to target a specific worker.
def memory_sample(duration: 10, connection_id:)
	client do |connection|
		Console.info(self, "Sampling memory from worker...", duration: duration, connection_id: connection_id)
		
		supervisor = connection[:supervisor]
		worker = supervisor[connection_id]
		return worker.memory_sample(duration: duration)
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
