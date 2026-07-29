# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "bake/context"

describe "async:service:supervisor" do
	let(:context) {@@context ||= Bake::Context.load}
	let(:supervisor) {Object.new}
	let(:worker) {Object.new}
	let(:result) {Object.new}
	let(:connection) do
		{supervisor: supervisor}
	end
	
	def invoke(name, **options)
		recipe = context.lookup("async:service:supervisor:#{name}")
		result = nil
		
		mock(recipe.instance) do |mock|
			mock.replace(:client) do |&block|
				block.call(connection)
			end
			
			result = recipe.call(**options)
		end
		
		result
	end
	
	def invoke_worker(name, connection_id: 7, **options)
		result = nil
		
		mock(supervisor) do |mock|
			mock.replace(:[]) do |id|
				expect(id).to be == connection_id
				worker
			end
			
			result = invoke(name, connection_id: connection_id, **options)
		end
		
		result
	end
	
	it "lists the workers" do
		mock(supervisor) do |mock|
			mock.replace(:keys){[1, 2, 3]}
			
			expect(invoke("workers")).to be == [1, 2, 3]
		end
	end
	
	it "dumps memory" do
		mock(worker) do |mock|
			mock.replace(:memory_dump) do |path:|
				expect(path).to be == "/tmp/memory.json"
				result
			end
			
			expect(invoke_worker("memory_dump", path: "/tmp/memory.json")).to be == result
		end
	end
	
	it "dumps the scheduler" do
		mock(worker) do |mock|
			mock.replace(:scheduler_dump) do |path:, log:|
				expect(path).to be == "/tmp/scheduler.txt"
				expect(log).to be == "Scheduler dump"
				result
			end
			
			expect(invoke_worker("scheduler_dump", path: "/tmp/scheduler.txt", log: "Scheduler dump")).to be == result
		end
	end
	
	it "dumps the threads" do
		mock(worker) do |mock|
			mock.replace(:thread_dump) do |path:|
				expect(path).to be == "/tmp/threads.txt"
				result
			end
			
			expect(invoke_worker("thread_dump", path: "/tmp/threads.txt")).to be == result
		end
	end
	
	it "starts garbage collection profiling" do
		mock(worker) do |mock|
			mock.replace(:garbage_profile_start){result}
			
			expect(invoke_worker("garbage_profile_start")).to be == result
		end
	end
	
	it "stops garbage collection profiling" do
		mock(worker) do |mock|
			mock.replace(:garbage_profile_stop) do |path:|
				expect(path).to be == "/tmp/gc.txt"
				result
			end
			
			expect(invoke_worker("garbage_profile_stop", path: "/tmp/gc.txt")).to be == result
		end
	end
end
