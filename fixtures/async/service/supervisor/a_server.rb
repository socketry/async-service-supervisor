# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "sus/fixtures/async/scheduler_context"
require "async/service/supervisor"

require "io/endpoint/bound_endpoint"
require "tmpdir"

module Async
	module Service
		module Supervisor
			class RegistrationMonitor
				Event = Struct.new(:type, :supervisor_controller)
				
				def initialize
					@registrations = ::Thread::Queue.new
				end
				
				attr :registrations
				
				def run
				end
				
				def status
					{registrations: @registrations.size}
				end
				
				def pop(...)
					@registrations.pop(...)
				end
				
				def register(supervisor_controller)
					@registrations << Event.new(:register, supervisor_controller)
				end
				
				def remove(supervisor_controller)
					@registrations << Event.new(:remove, supervisor_controller)
				end
			end
			
			AServer = Sus::Shared("a server") do
				include Sus::Fixtures::Async::SchedulerContext
				
				let(:ipc_path) {File.join(@root, "supervisor.ipc")}
				let(:endpoint) {Async::Service::Supervisor.endpoint(ipc_path)}
				
				def around
					Dir.mktmpdir do |directory|
						@root = directory
						super
					end
				end
				
				let(:registration_monitor) {RegistrationMonitor.new}
				let(:monitors) {[registration_monitor]}
				let(:server) {Async::Service::Supervisor::Server.new(endpoint: @bound_endpoint, monitors: monitors)}
				
				def restart_supervisor
					@server_task&.stop
					
					@server_task = reactor.async do
						server.run
					end
				end
				
				before do
					@bound_endpoint = endpoint.bound
					
					@server_task = reactor.async do
						server.run
					end
				end
				
				after do
					@server_task&.stop
					@bound_endpoint&.close
				end
			end
		end
	end
end

