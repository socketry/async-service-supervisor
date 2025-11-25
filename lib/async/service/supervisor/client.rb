# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/client"

module Async
	module Service
		module Supervisor
			# A client provides a mechanism to connect to a supervisor server in order to execute operations.
			class Client < Async::Bus::Client
				# Initialize a new client.
				#
				# @parameter endpoint [IO::Endpoint] The supervisor endpoint to connect to.
				def initialize(endpoint: Supervisor.endpoint, **options)
					super(endpoint, **options)
				end
			end
		end
	end
end
