# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/monitor"
require "sus/fixtures/async/scheduler_context"

describe Async::Service::Supervisor::Monitor do
	let(:monitor) {subject.new}
	
	with "#as_json" do
		it "returns an empty hash" do
			expect(monitor.as_json).to be == {}
		end
	end
	
	with "#to_json" do
		it "serializes to a JSON string" do
			expect(monitor.to_json).to be == "{}"
		end
	end
	
	with "#status" do
		it "returns a hash with type and data keys" do
			status = monitor.status
			expect(status).to have_keys(
				type: be == "Async::Service::Supervisor::Monitor",
				data: be == {}
			)
		end
	end
	
	with "#run_once" do
		it "does nothing by default" do
			expect{monitor.run_once}.not.to raise_exception
		end
	end
	
	with "#run" do
		include Sus::Fixtures::Async::SchedulerContext
		
		it "returns a running task" do
			task = monitor.run
			expect(task).to be(:running?)
		ensure
			task&.stop
		end
		
		it "respects the interval option" do
			monitor = subject.new(interval: 0.1)
			task = monitor.run
			expect(task).to be(:running?)
		ensure
			task&.stop
		end
	end
end
