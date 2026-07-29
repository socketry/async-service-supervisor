# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "bake/context"

describe "async:service:supervisor" do
	let(:context) {@@context ||= Bake::Context.load}
	let(:worker) {Object.new}
	let(:result) {Object.new}
	
	def invoke(name, connection_id: 7, **options)
		recipe = context.lookup("async:service:supervisor:#{name}")
		
		mock(recipe.instance) do |mock|
			mock.replace(:with_worker) do |id, &block|
				expect(id).to be == connection_id
				block.call(worker)
			end
			
			return recipe.call(connection_id: connection_id, **options)
		end
	end
	
	it "lists the workers" do
		recipe = context.lookup("async:service:supervisor:workers")
		supervisor = Object.new
		connection = Object.new
		supervisor.define_singleton_method(:keys) {[1, 2, 3]}
		connection.define_singleton_method(:[]) do |name|
			raise ArgumentError, "Unexpected controller: #{name.inspect}" unless name == :supervisor
			supervisor
		end
		
		mock(recipe.instance) do |mock|
			mock.replace(:client) {|&block| block.call(connection)}
			
			expect(recipe.call).to be == [1, 2, 3]
		end
	end
	
	it "dumps memory" do
		mock(worker) do |mock|
			mock.replace(:memory_dump) do |path:|
				expect(path).to be == "/tmp/memory.json"
				result
			end
			
			expect(invoke("memory_dump", path: "/tmp/memory.json")).to be == result
		end
	end
	
	it "dumps the scheduler" do
		mock(worker) do |mock|
			mock.replace(:scheduler_dump) do |path:, log:|
				expect(path).to be == "/tmp/scheduler.txt"
				expect(log).to be == "Scheduler dump"
				result
			end
			
			expect(invoke("scheduler_dump", path: "/tmp/scheduler.txt", log: "Scheduler dump")).to be == result
		end
	end
	
	it "dumps the threads" do
		mock(worker) do |mock|
			mock.replace(:thread_dump) do |path:|
				expect(path).to be == "/tmp/threads.txt"
				result
			end
			
			expect(invoke("thread_dump", path: "/tmp/threads.txt")).to be == result
		end
	end
	
	it "starts garbage collection profiling" do
		mock(worker) do |mock|
			mock.replace(:garbage_profile_start) {result}
			
			expect(invoke("garbage_profile_start")).to be == result
		end
	end
	
	it "stops garbage collection profiling" do
		mock(worker) do |mock|
			mock.replace(:garbage_profile_stop) do |path:|
				expect(path).to be == "/tmp/gc.txt"
				result
			end
			
			expect(invoke("garbage_profile_stop", path: "/tmp/gc.txt")).to be == result
		end
	end
end
