# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/service/supervisor/a_server"
require "sus/fixtures/console/captured_logger"

describe Async::Service::Supervisor::Server do
	include Async::Service::Supervisor::AServer
	include Sus::Fixtures::Console::CapturedLogger
	
	with "failing monitor" do
		let(:failing_monitor) do
			Class.new do
				def run
				end
				
				def register(supervisor_controller)
					raise "Monitor failed to register!"
				end
				
				def remove(supervisor_controller)
					raise "Monitor failed to remove!"
				end
				
				def status
					raise "Monitor failed to get status!"
				end
			end.new
		end
		
		let(:monitors) {[failing_monitor, registration_monitor]}
		
		it "can handle monitor registration failures" do
			# Connect a worker which will trigger registration
			worker = Async::Service::Supervisor::Worker.new(process_id: ::Process.pid, endpoint: endpoint)
			worker_task = worker.run
			
			# Wait for registration:
			registration_monitor.pop
			
			# Verify error was logged about the monitor failure:
			error_log = console_capture.find{|log| log[:severity] == :error && log[:message] =~ /Error while registering process/}
			expect(error_log).to be_truthy
		ensure
			worker_task&.stop
		end
		
		it "can handle monitor status failures" do
			# Create a client and request status
			client = Async::Service::Supervisor::Client.new(endpoint: endpoint)
			
			client.connect do |connection|
				supervisor = connection[:supervisor]
				
				# Status should still work even if monitor fails
				# The monitor error is logged but doesn't break status
				result = supervisor.status
				
				# Status returns an array of monitor statuses
				expect(result).to be_a(Array)
			end
		end
		
		it "can handle monitor removal failures" do
			# Connect then disconnect to trigger removal:
			worker = Async::Service::Supervisor::Worker.new(process_id: ::Process.pid, endpoint: endpoint)
			worker_task = worker.run
			
			# Wait for registration:
			registration_monitor.pop
			
			# Stop worker to trigger removal
			worker_task.stop
			
			# Wait for removal:
			registration_monitor.pop
			
			# Verify error was logged about the monitor removal failure:
			error_log = console_capture.find{|log| log[:severity] == :error && log[:message] =~ /Error while removing process/}
			expect(error_log).to be_truthy
			
			# Verify server is still working by sending a new request:
			client = Async::Service::Supervisor::Client.new(endpoint: endpoint)
			client.connect do |connection|
				supervisor = connection[:supervisor]
				result = supervisor.status
				expect(result).to be_a(Array)
			end
		end
	end
end

