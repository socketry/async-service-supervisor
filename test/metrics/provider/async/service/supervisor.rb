# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "metrics"
require "metrics/provider/async/service/supervisor"

require "async/service/supervisor/process_monitor"
require "async/service/supervisor/utilization_monitor"

describe "metrics/provider/async/service/supervisor" do
	def metric(owner, name)
		owner.const_get(name, false)
	end
	
	it "scopes metric constants to the instrumented classes" do
		expect(Object.const_defined?(:PROCESS_METRICS_GENERAL_PROCESSOR_UTILIZATION, false)).to be == false
		expect(Object.const_defined?(:UTILIZATION, false)).to be == false
		expect(Object.const_defined?(:UTILIZATION_WORKERS, false)).to be == false
		
		expect(Async::Service::Supervisor::ProcessMonitor.const_defined?(:PROCESS_METRICS_GENERAL_PROCESSOR_UTILIZATION, false)).to be == true
		expect(Async::Service::Supervisor::UtilizationMonitor.const_defined?(:UTILIZATION, false)).to be == true
		expect(Async::Service::Supervisor::UtilizationMonitor.const_defined?(:UTILIZATION_WORKERS, false)).to be == true
	end
	
	it "defines process monitor metrics" do
		metric = metric(Async::Service::Supervisor::ProcessMonitor, :PROCESS_METRICS_GENERAL_PROCESSOR_UTILIZATION)
		
		expect(metric.name).to be == "process.metrics.general.processor_utilization"
		expect(metric.type).to be == :gauge
	end
	
	it "emits process monitor metrics" do
		monitor = Async::Service::Supervisor::ProcessMonitor.new
		
		expect(metric(Async::Service::Supervisor::ProcessMonitor, :PROCESS_METRICS_GENERAL_PROCESSOR_UTILIZATION)).to receive(:emit).with(10.5).once
		expect(metric(Async::Service::Supervisor::ProcessMonitor, :PROCESS_METRICS_GENERAL_TOTAL_SIZE)).to receive(:emit).with(2048).once
		expect(metric(Async::Service::Supervisor::ProcessMonitor, :PROCESS_METRICS_GENERAL_VIRTUAL_SIZE)).to receive(:emit).with(4096).once
		expect(metric(Async::Service::Supervisor::ProcessMonitor, :PROCESS_METRICS_GENERAL_RESIDENT_SIZE)).to receive(:emit).with(1024).once
		
		monitor.emit(
			1234 => {
				process_id: 1234,
				parent_process_id: 12,
				process_group_id: 34,
				processor_utilization: 10.5,
				total_size: 2048,
				virtual_size: 4096,
				resident_size: 1024,
			}
		)
	end
	
	it "defines utilization monitor metrics" do
		metric = metric(Async::Service::Supervisor::UtilizationMonitor, :UTILIZATION)
		
		expect(metric.name).to be == "async.utilization"
		expect(metric.type).to be == :gauge
	end
	
	it "emits utilization monitor metrics" do
		monitor = Async::Service::Supervisor::UtilizationMonitor.allocate
		tags = Metrics::Tags.normalize(service: "test_service")
		
		expect(metric(Async::Service::Supervisor::UtilizationMonitor, :UTILIZATION_CONNECTIONS_ACTIVE)).to receive(:emit).with(4, tags: tags).once
		expect(metric(Async::Service::Supervisor::UtilizationMonitor, :UTILIZATION_CONNECTIONS_TOTAL)).to receive(:emit).with(10, tags: tags).once
		expect(metric(Async::Service::Supervisor::UtilizationMonitor, :UTILIZATION_REQUESTS_ACTIVE)).to receive(:emit).with(2, tags: tags).once
		expect(metric(Async::Service::Supervisor::UtilizationMonitor, :UTILIZATION_REQUESTS_TOTAL)).to receive(:emit).with(6, tags: tags).once
		expect(metric(Async::Service::Supervisor::UtilizationMonitor, :UTILIZATION_WORKERS)).to receive(:emit).with(2, tags: tags).once
		expect(metric(Async::Service::Supervisor::UtilizationMonitor, :UTILIZATION)).to receive(:emit).with(1.0, tags: tags).once
		
		monitor.emit(
			"test_service" => {
				connections_active: 4,
				connections_total: 10,
				requests_active: 2,
				requests_total: 6,
				unknown_depth: 7,
				worker_count: 2,
			}
		)
	end
end
