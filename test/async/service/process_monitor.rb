# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "async/service/supervisor/process_monitor"
require "async/service/supervisor/a_monitor"

require "sus/fixtures/console/captured_logger"

describe Async::Service::Supervisor::ProcessMonitor do
	include Sus::Fixtures::Console::CapturedLogger
	
	let(:monitor) {subject.new(interval: 1)}
	it_behaves_like Async::Service::Supervisor::AMonitor
	
	with "#ppid" do
		it "defaults to the current parent process id" do
			expect(monitor.ppid).to be == Process.ppid
		end
		
		it "can be set explicitly" do
			monitor = subject.new(ppid: 1)
			expect(monitor.ppid).to be == 1
		end
	end
	
	with "#metrics" do
		it "returns a hash of process metrics" do
			metrics = monitor.metrics
			expect(metrics).to be_a(Hash)
			expect(metrics).not.to be(:empty?)
		end
	end
	
	with "#emit" do
		it "logs each process" do
			metrics = {
				1234 => {process_id: 1234, command: "ruby"},
				5678 => {process_id: 5678, command: "worker"},
			}
			
			monitor.emit(metrics)
			
			expect(console_capture.records.length).to be == 2
		end
	end
	
	with "#run_once" do
		it "captures metrics and passes them to emit" do
			emitted = nil
			monitor.define_singleton_method(:emit){|metrics| emitted = metrics}
			
			monitor.run_once
			
			expect(emitted).to be_a(Hash)
			expect(emitted).not.to be(:empty?)
		end
	end
	
	it "supports subclass overriding emit" do
		received = nil
		
		subclass = Class.new(subject) do
			define_method(:emit) do |metrics|
				received = metrics
				super(metrics)
			end
		end
		
		sub_monitor = subclass.new(interval: 1)
		sub_monitor.run_once
		
		expect(received).to be_a(Hash)
		expect(received).not.to be(:empty?)
	end
	
	with "#run" do
		include Sus::Fixtures::Async::SchedulerContext
		
		it "can run the monitor" do
			task = monitor.run
			expect(task).to be(:running?)
		end
		
		it "can handle failures" do
			expect(monitor).to receive(:metrics).and_raise(Errno::ESRCH)
			
			task = monitor.run
			expect(task).to be(:running?)
			
			sleep 1
			
			expect(task).to be(:running?)
		end
	end
end

