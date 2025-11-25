# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/server"
require_relative "supervisor_controller"
require_relative "worker_controller"

module Async
	module Service
		module Supervisor
			# The server represents the main supervisor process which is responsible for managing the lifecycle of other processes.
			#
			# There are various tasks that can be executed by the server, such as restarting the process group, and querying the status of the processes. The server is also responsible for managing the lifecycle of the monitors, which can be used to monitor the status of the connected workers.
			class Server < Async::Bus::Server
				# Initialize a new supervisor server.
				#
				# @parameter monitors [Array] The monitors to run.
				# @parameter endpoint [IO::Endpoint] The endpoint to listen on.
				def initialize(monitors: [], endpoint: Supervisor.endpoint, **options)
					super(endpoint, **options)
					
					@monitors = monitors
					@controllers = {}
					@next_id = 0
				end
				
				attr :monitors
				attr :controllers
				
				# Allocate the next unique sequential ID.
				#
				# @returns [Integer] A unique sequential ID.
				def next_id
					@next_id += 1
				end
				
				# Add a controller to the server.
				#
				# Validates that the controller has been properly registered with an ID
				# and checks for ID collisions before adding it to tracking.
				#
				# @parameter controller [SupervisorController] The controller to add.
				# @raises [RuntimeError] If the controller doesn't have an ID or if there's an ID collision.
				def add(controller)
					unless id = controller.id
						raise RuntimeError, "Controller must be registered with an ID before being added!"
					end
					
					if @controllers.key?(id)
						raise RuntimeError, "Controller already registered: id=#{id}"
					end
					
					@controllers[id] = controller
					
					# Notify monitors with the supervisor controller:
					@monitors.each do |monitor|
						monitor.register(controller)
					rescue => error
						Console.error(self, "Error while registering process!", monitor: monitor, exception: error)
					end
				end
				
				# Remove a worker connection from the supervisor.
				#
				# Notifies all monitors and removes the connection from tracking.
				#
				# @parameter connection [Protocol::Connection] The connection to remove.
				def remove(controller)
					if id = controller.id
						@controllers.delete(id)
					end
					
					# Notify monitors with the supervisor controller:
					@monitors.each do |monitor|
						monitor.remove(controller)
					rescue => error
						Console.error(self, "Error while removing process!", monitor: monitor, exception: error)
					end
				end
				
				# Run the supervisor server.
				#
				# Starts all monitors and accepts connections from workers.
				#
				# @parameter parent [Async::Task] The parent task to run under.
				def run
					Sync do |task|
						# Start all monitors:
						@monitors.each do |monitor|
							monitor.run
						rescue => error
							Console.error(self, "Error while starting monitor!", monitor: monitor, exception: error)
						end
						
						# Accept connections from workers:
						self.accept do |connection|
							# Create a supervisor controller for this connection:
							supervisor_controller = SupervisorController.new(self, connection)
							
							# Bind supervisor controller:
							connection.bind(:supervisor, supervisor_controller)
							
							# Run the connection:
							connection.run
						ensure
							self.remove(supervisor_controller)
						end
						
						task.children&.each(&:wait)
					ensure
						task.stop
					end
				end
			end
		end
	end
end

