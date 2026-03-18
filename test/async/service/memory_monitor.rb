# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "memory/leak/monitor"

require "async/service/supervisor/memory_monitor"
require "async/service/supervisor/a_monitor"

require "sus/fixtures/console/captured_logger"

Controller = Data.define(:process_id, :worker)

describe Async::Service::Supervisor::MemoryMonitor do
	include Sus::Fixtures::Console::CapturedLogger
	
	let(:monitor) {subject.new(interval: 1)}
	it_behaves_like Async::Service::Supervisor::AMonitor
	
	with "#run" do
		include Sus::Fixtures::Async::SchedulerContext
		
		it "can run the monitor" do
			task = monitor.run
			expect(task).to be(:running?)
		end
		
		it "can handle failures" do
			expect(monitor.cluster).to receive(:check!).and_raise(Errno::ESRCH)
			
			task = monitor.run
			expect(task).to be(:running?)
			
			sleep 1
			
			expect(task).to be(:running?)
		end
	end
	
	with "#handle_leaking_process" do
		let(:process_id) {99999}
		let(:memory_monitor) {Memory::Leak::Monitor.new(process_id, maximum_size_limit: 100)}
		
		let(:worker_proxy) do
			mock(Object.new) {|mock| mock.replace(:garbage_collect){nil}}
		end
		
		let(:controller) {Controller.new(process_id: process_id, worker: worker_proxy)}
		
		it "kills immediately when no supervisor controller" do
			expect(Process).to receive(:kill).with(:INT, process_id)
			
			monitor.handle_leaking_process(process_id, memory_monitor)
		end
		
		it "kills immediately when supervisor controller has no worker" do
			controller = Controller.new(process_id: process_id, worker: nil)
			monitor.register(controller)
			
			expect(Process).to receive(:kill).with(:INT, process_id)
			monitor.handle_leaking_process(process_id, memory_monitor)
		end
		
		it "invokes GC via RPC on first exceed, adds to exceeded" do
			gc_proxy = mock(Object.new) do |mock|
				mock.replace(:garbage_collect) do |full_mark: true, immediate_sweep: true|
					expect(full_mark).to be == true
					expect(immediate_sweep).to be == true
					nil
				end
			end
			
			monitor.register(Controller.new(process_id: process_id, worker: gc_proxy))
			
			mock(monitor.cluster) do |mock|
				mock.replace(:check!){|&block| block.call(process_id, memory_monitor)}
			end
			
			exceeded = monitor.check_cluster
			expect(exceeded).to be(:include?, process_id)
		end
		
		it "kills when in exceeded and still leaking" do
			monitor.register(controller)
			
			mock(monitor.cluster) do |mock|
				mock.replace(:check!){|&block| block.call(process_id, memory_monitor)}
			end
			
			expect(Process).to receive(:kill).with(:INT, process_id)
			
			exceeded = monitor.check_cluster
			expect(exceeded).to be(:include?, process_id)
			
			exceeded = monitor.check_cluster
			expect(exceeded).to be(:include?, process_id)
		end
		
		it "removes from exceeded when no longer reported" do
			monitor.register(controller)
			
			call_count = 0
			mock(monitor.cluster) do |mock|
				mock.replace(:check!) do |&block|
					call_count += 1
					block.call(process_id, memory_monitor) if call_count == 1
				end
			end
			
			exceeded = monitor.check_cluster
			expect(exceeded).to be(:include?, process_id)
			
			exceeded = monitor.check_cluster
			expect(exceeded).not.to be(:include?, process_id)
		end
		
		it "kills when GC RPC fails" do
			failing_proxy = Object.new
			expect(failing_proxy).to receive(:garbage_collect).and_raise(StandardError, "Connection closed")
			monitor.register(Controller.new(process_id: process_id, worker: failing_proxy))
			
			expect(Process).to receive(:kill).with(:INT, process_id)
			monitor.handle_leaking_process(process_id, memory_monitor)
		end
	end
	
	with "#remove" do
		let(:pid) {88888}
		let(:memory_monitor) {Memory::Leak::Monitor.new(pid, maximum_size_limit: 100)}
		
		let(:worker_proxy) do
			mock(Object.new) {|mock| mock.replace(:garbage_collect){nil}}
		end
		
		let(:controller) {Controller.new(process_id: pid, worker: worker_proxy)}
		
		it "removes process from exceeded set" do
			monitor.register(controller)
			
			call_count = 0
			mock(monitor.cluster) do |mock|
				mock.replace(:check!) do |&block|
					call_count += 1
					block.call(pid, memory_monitor) if call_count == 1
				end
			end
			
			exceeded = monitor.check_cluster
			expect(exceeded).to be(:include?, pid)
			
			monitor.remove(controller)
			
			exceeded = monitor.check_cluster
			expect(exceeded).not.to be(:include?, pid)
		end
	end
end

