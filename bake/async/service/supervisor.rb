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

private

def endpoint
	Async::Service::Supervisor.endpoint
end

def client(&block)
	Sync do
		Async::Service::Supervisor::Client.new(endpoint: self.endpoint).connect(&block)
	end
end
