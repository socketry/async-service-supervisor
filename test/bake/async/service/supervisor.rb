# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "bake/context"
require "async/service/supervisor/a_simple_service"

describe "async:service:supervisor" do
	include_context Async::Service::Supervisor::ASimpleService
	
	let(:context) {@@context ||= Bake::Context.load}
	
	def invoke(name, **options)
		recipe = context.lookup("async:service:supervisor:#{name}")
		result = nil
		
		mock(recipe.instance) do |mock|
			mock.replace(:endpoint){endpoint}
			result = recipe.call(**options)
		end
		
		result
	end
	
	it "lists the workers" do
		expect(invoke("workers")).to be == [connection_id]
	end
	
	it "dumps memory" do
		path = File.join(@root, "memory.json")
		result = invoke("memory_dump", connection_id: connection_id, path: path)
		
		expect(result).to be == {path: path}
		expect(File.size(path)).to be > 0
	end
	
	it "dumps the scheduler" do
		path = File.join(@root, "scheduler.txt")
		result = invoke("scheduler_dump", connection_id: connection_id, path: path)
		
		expect(result).to be == {path: path}
		expect(File.size(path)).to be > 0
	end
	
	it "dumps the threads" do
		path = File.join(@root, "threads.txt")
		result = invoke("thread_dump", connection_id: connection_id, path: path)
		
		expect(result).to be == {path: path}
		expect(File.size(path)).to be > 0
	end
	
	it "starts garbage collection profiling" do
		result = invoke("garbage_profile_start", connection_id: connection_id)
		
		expect(result).to be == {started: true}
		expect(GC::Profiler.enabled?).to be == true
	end
	
	it "stops garbage collection profiling" do
		path = File.join(@root, "gc.txt")
		
		invoke("garbage_profile_start", connection_id: connection_id)
		result = invoke("garbage_profile_stop", connection_id: connection_id, path: path)
		
		expect(result).to be == {path: path}
		expect(File).to be(:exist?, path)
		expect(GC::Profiler.enabled?).to be == false
	end
end
