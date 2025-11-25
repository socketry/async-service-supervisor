# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/controller"
require "stringio"

module Async
	module Service
		module Supervisor
			# Controller for worker operations.
			#
			# Handles diagnostic operations like memory dumps, thread dumps, scheduler dumps, etc.
			class WorkerController < Async::Bus::Controller
				def initialize(worker)
					@worker = worker
				end
				
				private def dump(path: nil, log: nil, buffer: true, &block)
					if path
						File.open(path, "w") do |file|
							yield file
						end
						
						return {path: path}
					elsif buffer
						buffer = StringIO.new
						yield buffer
						
						if log
							Console.info(self, log, data: buffer.string)
							return {}
						else
							return {data: buffer.string}
						end
					else
						raise ArgumentError, "Buffered output not supported!"
					end
				end
				
				# Dump the current fiber scheduler hierarchy.
				#
				# Generates a hierarchical view of all running fibers and their relationships.
				#
				# @parameter path [String] Optional file path to save the dump.
				# @parameter log [String] Optional log message to output.
				def scheduler_dump(path: nil, log: nil)
					dump(path: path, log: log) do |file|
						Fiber.scheduler.print_hierarchy(file)
					end
				end
				
				# Dump the entire object space to a file.
				#
				# This is a heavyweight operation that dumps all objects in the heap.
				# Consider using {memory_sample} for lighter weight memory leak detection.
				#
				# @parameter path [String] Optional file path to save the dump.
				def memory_dump(path: nil)
					require "objspace"
					
					dump(path: path, buffer: false) do |file|
						ObjectSpace.dump_all(output: file)
					end
				end
				
				# Sample memory allocations over a time period to identify potential leaks.
				#
				# This method is much lighter weight than {memory_dump} and focuses on
				# retained objects allocated during the sampling period. Late-lifecycle
				# allocations that are retained are likely memory leaks.
				#
				# The method samples allocations for the specified duration, forces a garbage
				# collection, and returns a JSON report showing allocated vs retained memory
				# broken down by gem, file, location, and class.
				#
				# @parameter duration [Numeric] The duration in seconds to sample for.
				# @parameter path [String] Optional file path to save the sample.
				def memory_sample(duration:, path: nil)
					require "memory"
					
					unless duration.positive?
						raise ArgumentError, "Positive duration is required!"
					end
					
					Console.info(self, "Starting memory sampling...", duration: duration)
					
					# Create a sampler to track allocations
					sampler = Memory::Sampler.new
					
					# Start sampling
					sampler.start
					
					# Sample for the specified duration
					sleep(duration)
					
					# Stop sampling
					sampler.stop
					
					report = sampler.report
					
					dump(path: path) do |file|
						file.puts(report.to_s)
					end
				ensure
					GC.start
				end
				
				# Dump information about all running threads.
				#
				# Includes thread inspection and backtraces for debugging.
				#
				# @parameter path [String] Optional file path to save the dump.
				def thread_dump(path: nil)
					dump(path: path) do |file|
						Thread.list.each do |thread|
							file.puts(thread.inspect)
							file.puts(thread.backtrace)
						end
					end
				end
				
				# Start garbage collection profiling.
				#
				# Enables the GC profiler to track garbage collection performance.
				#
				# @returns [Hash] Confirmation that profiling started.
				def garbage_profile_start
					GC::Profiler.enable
					return {started: true}
				end
				
				# Stop garbage collection profiling and return results.
				#
				# Disables the GC profiler and returns collected profiling data.
				#
				# @parameter path [String] Optional file path to save the profile.
				def garbage_profile_stop(path: nil)
					dump(path: path) do |file|
						file.puts GC::Profiler.result
					end
				ensure
					GC::Profiler.disable
				end
			end
		end
	end
end

