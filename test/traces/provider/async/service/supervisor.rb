# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "traces"
require "traces/provider/async/service/supervisor"

require "async/service/supervisor/server"
require "async/service/supervisor/supervisor_controller"

describe "traces/provider/async/service/supervisor" do
	def server
		Async::Service::Supervisor::Server.new(endpoint: IO::Endpoint.unix("test.ipc"))
	end
	
	it "traces worker registration" do
		server = self.server
		connection = Object.new
		controller = Async::Service::Supervisor::SupervisorController.new(server, connection)
		worker = Object.new
		
		expect(Traces).to receive(:trace).with(
			"async.service.supervisor.worker.register",
			attributes: {
				"worker.process_id" => 1234,
				"service.name" => "test_service",
				"monitor.count" => 0,
			}
		)
		
		id = controller.register(worker, process_id: 1234, state: {name: "test_service"})
		
		expect(id).to be == 1
	end
	
	it "traces worker removal" do
		server = self.server
		connection = Object.new
		controller = Async::Service::Supervisor::SupervisorController.new(server, connection)
		worker = Object.new
		
		controller.register(worker, process_id: 1234, state: {name: "test_service"})
		
		expect(Traces).to receive(:trace).with(
			"async.service.supervisor.worker.remove",
			attributes: {
				"worker.id" => 1,
				"worker.process_id" => 1234,
				"service.name" => "test_service",
				"monitor.count" => 0,
			}
		)
		
		server.remove(controller)
		
		expect(server.controllers).to be(:empty?)
	end
end
