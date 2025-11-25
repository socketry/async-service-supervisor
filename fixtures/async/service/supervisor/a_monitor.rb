# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/service/supervisor/a_server"

module Async
	module Service
		module Supervisor
			AMonitor = Sus::Shared("a monitor") do
				include_context AServer
				
				let(:monitors) {[monitor, registration_monitor]}
				
				it "can add and remove connections" do
					worker = Worker.new(endpoint: endpoint)
					worker_task = worker.run
					
					event = registration_monitor.pop
					expect(event).to have_attributes(
						type: be == :register,
					)
					expect(event.supervisor_controller).to be_a(Async::Service::Supervisor::SupervisorController)
					
					worker_task.stop
					
					event = registration_monitor.pop
					expect(event).to have_attributes(
						type: be == :remove,
					)
				ensure
					worker_task&.stop
				end
				
				it "can respond to status calls" do
					client = Client.new(endpoint: endpoint)
					
					client.connect do |connection|
						supervisor = connection[:supervisor]
						response = supervisor.status
						
						# Status should return an array of monitor statuses
						expect(response).to be_a(Array)
					end
				end
			end
		end
	end
end


