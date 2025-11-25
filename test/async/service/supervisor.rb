# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/service/supervisor/a_server"

describe Async::Service::Supervisor do
	include Async::Service::Supervisor::AServer
	
	it "can connect to a server" do
		worker = Async::Service::Supervisor::Worker.new(process_id: ::Process.pid, endpoint: endpoint)
		worker_task = worker.run
		
		# Wait for registration via the registration monitor
		event = registration_monitor.pop(timeout: 5)
		
		expect(event).to be_truthy
		supervisor_controller = event.supervisor_controller
		
		expect(supervisor_controller.process_id).to be == ::Process.pid
	ensure
		worker_task&.stop
	end
	
	with "memory_dump" do
		it "can dump memory" do
			worker = Async::Service::Supervisor::Worker.new(process_id: ::Process.pid, endpoint: endpoint)
			worker_task = worker.run
			
			# Wait for registration via the registration monitor
			event = registration_monitor.pop(timeout: 5)
			expect(event).to be_truthy
			supervisor_controller = event.supervisor_controller
			connection = supervisor_controller.connection
			
			# Get the worker controller proxy
			worker_controller = connection[:worker]
			
			path = File.join(@root, "memory.json")
			result = worker_controller.memory_dump(path: path)
			
			expect(result).to have_keys(:path)
			expect(File.size(result[:path])).to be > 0
		ensure
			worker_task&.stop
		end
	end
	
	with "array-like access" do
		it "gets worker proxy via connection_id and invokes operations" do
			worker = Async::Service::Supervisor::Worker.new(process_id: ::Process.pid, endpoint: endpoint)
			worker_task = worker.run
			
			# Wait for worker to register via the registration monitor
			event = registration_monitor.pop(timeout: 5)
			expect(event).to be_truthy
			supervisor_controller = event.supervisor_controller
			connection_id = supervisor_controller.id
			expect(connection_id).to be_truthy
			
			# Create a client connection to the supervisor
			client = Async::Service::Supervisor::Client.new(endpoint: endpoint)
			client.connect do |connection|
				supervisor = connection[:supervisor]
				
				# Get the worker proxy using array-like access and invoke memory_sample directly
				worker_proxy = supervisor[connection_id]
				result = worker_proxy.memory_sample(duration: 1)
				
				# Verify we got the response
				expect(result).to have_keys(:data)
			end
		ensure
			worker_task&.stop
		end
		
		it "fails when accessing non-existent connection_id" do
			# Create a client connection (no worker registered)
			client = Async::Service::Supervisor::Client.new(endpoint: endpoint)
			
			client.connect do |connection|
				supervisor = connection[:supervisor]
				
				expect do
					supervisor[99999]
				end.to raise_exception(ArgumentError, message: be =~ /Connection not found/)
			end
		end
		
		it "can list all registered workers" do
			worker = Async::Service::Supervisor::Worker.new(process_id: ::Process.pid, endpoint: endpoint)
			worker_task = worker.run
			
			# Wait for worker to register via the registration monitor
			event = registration_monitor.pop(timeout: 5)
			expect(event).to be_truthy
			supervisor_controller = event.supervisor_controller
			connection_id = supervisor_controller.id
			expect(connection_id).to be_truthy
			
			# Create a client connection to the supervisor
			client = Async::Service::Supervisor::Client.new(endpoint: endpoint)
			client.connect do |connection|
				supervisor = connection[:supervisor]
				
				# List all workers using keys method
				worker_ids = supervisor.keys
				expect(worker_ids).to be(:include?, connection_id)
			end
		ensure
			worker_task&.stop
		end
	end
	
	with "memory_sample" do
		it "can sample memory allocations" do
			worker = Async::Service::Supervisor::Worker.new(process_id: ::Process.pid, endpoint: endpoint)
			worker_task = worker.run
			
			# Wait for registration via the registration monitor
			event = registration_monitor.pop(timeout: 5)
			expect(event).to be_truthy
			supervisor_controller = event.supervisor_controller
			connection = supervisor_controller.connection
			
			# Get the worker controller proxy
			worker_controller = connection[:worker]
			
			# Sample for a short duration (1 second for test speed)
			result = worker_controller.memory_sample(duration: 1)
			
			# The result should contain a report
			expect(result).to have_keys(:data)
		ensure
			worker_task&.stop
		end
	end
end

