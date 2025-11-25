# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/service/supervisor/a_server"
require "async/service/supervisor/supervised"

class SleepService < Async::Service::Generic
	def setup(container)
		super
		
		container.spawn(name: self.class.name) do |instance|
			Async do
				evaluator = self.environment.evaluator
				
				evaluator.prepare!(instance)
				
				instance.ready!
				
				sleep
			end
		end
	end	
end

describe Async::Service::Supervisor::Supervised do
	include Async::Service::Supervisor::AServer
	
	let(:state) do
		{process_id: ::Process.pid}
	end
	
	it "can define a supervised service" do
		environment = Async::Service::Environment.build(root: @root) do
			service_class {SimpleService}
			
			include Async::Service::Supervisor::Supervised
		end
		
		evaluator = environment.evaluator
		# Get the supervisor worker for this process
		worker = evaluator.supervisor_worker
		worker_task = worker.run
		
		# Wait for the worker to register with the supervisor.
		event = registration_monitor.pop
		supervisor_controller = event.supervisor_controller
		
		expect(supervisor_controller.process_id).to be == ::Process.pid
	ensure
		worker_task&.stop
	end
end

