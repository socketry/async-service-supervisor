#!/usr/bin/env async-service
# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor"
require "async/service/managed/service"
require "async/utilization"
require "io/endpoint/host_endpoint"

class EchoService < Async::Service::Managed::Service
	def initialize(...)
		super
		
		@bound_endpoint = nil
		@endpoint = nil
	end
	
	# Prepare the bound endpoint for the server.
	def start
		@endpoint = IO::Endpoint.tcp("127.0.0.1", 8080)
		
		Sync do
			@bound_endpoint = @endpoint.bound
		end
		
		Console.info(self, "Starting echo server on #{@endpoint}")
		
		super
	end
	
	def run(instance, evaluator)
		evaluator.prepare!(instance)
		
		instance.ready!
		
		registry = evaluator.utilization_registry
		connections_total = registry.metric(:connections_total)
		connections_active = registry.metric(:connections_active)
		messages_total = registry.metric(:messages_total)
		
		Async do |task|
			@bound_endpoint.accept do |peer|
				connections_total.increment
				connections_active.track do
					Console.info(self, "Client connected", peer: peer)
					
					peer.each_line do |line|
						messages_total.increment
						peer.write(line)
					end
					
					Console.info(self, "Client disconnected", peer: peer)
				end
			end
		end
		
		# Return the bound endpoint for health checking
		@bound_endpoint
	end
	
	# Close the bound endpoint.
	def stop(...)
		if @bound_endpoint
			@bound_endpoint.close
			@bound_endpoint = nil
		end
		
		@endpoint = nil
		
		super
	end
end

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

service "supervisor" do
	include Async::Service::Supervisor::Environment
	
	monitors do
		[
			Async::Service::Supervisor::UtilizationMonitor.new(
				path: "utilization.shm",
				interval: 1
			)
		]
	end
end
