require 'rubygems'
gem 'opentox-ruby-api-wrapper', '= 1.4.0'
require 'opentox-ruby-api-wrapper'
require "dm-is-tree"

LOGGER.progname = File.expand_path(__FILE__)

class Task
	include DataMapper::Resource
	property :id, Serial
	property :parent_id, Integer
	property :pid, Integer
	property :uri, String, :length => 255
	property :resource, String, :length => 255
	property :status, String, :default => "created"
	property :created_at, DateTime
	property :finished_at, DateTime

	is :tree, :order => :created_at
end

DataMapper.auto_upgrade!

get '/?' do
	response['Content-Type'] = 'text/uri-list'
	Task.all.collect{|t| t.uri}.join("\n") + "\n"
end

get '/:id/?' do
	response['Content-Type'] = 'application/x-yaml'
	task = Task.get(params[:id])
	task.to_yaml
end

# dynamic access to Task properties
get '/:id/:property/?' do
	response['Content-Type'] = 'text/plain'
	task = Task.get(params[:id])
	eval("task.#{params[:property]}").to_s
end

post '/?' do
	LOGGER.debug "Creating new task ..."
	task = Task.new
	task.save # needed to create id
	task.uri = url_for("/#{task.id}", :full)
	task.save
	response['Content-Type'] = 'text/uri-list'
	task.uri + "\n"
end

put '/:id/:status/?' do
	task = Task.get(params[:id])
	task.status = params[:status] unless /pid|parent/ =~ params[:status]
	case params[:status]
	when "completed"

		LOGGER.debug "Task " + params[:id].to_s + " completed"
		task.resource = params[:resource]
		task.finished_at = DateTime.now
		task.pid = nil
	when "pid"
		#LOGGER.debug "PID = " + params[:pid].to_s
		task.pid = params[:pid]
	when "parent"
		task.parent = Task.first(:uri => params[:uri])
	when /cancelled|failed/
		Process.kill(9,task.pid) unless task.pid.nil?
		task.pid = nil
		RestClient.put url_for("/#{self.parent.id}/#{params[:status]}"), {} unless self.parent.nil? # recursevly kill parent tasks
	end
	task.save
end

delete '/:id/?' do
	task = Task.get(params[:id])
	begin
		Process.kill(9,task.pid) unless task.pid.nil?
	rescue
		"Cannot kill task with pid #{task.pid}"
	end
	task.destroy!
	response['Content-Type'] = 'text/plain'
	"Task #{params[:id]} deleted."
end

delete '/?' do
	Task.all.each do |task|
		begin
			Process.kill(9,task.pid) unless task.pid.nil?
		rescue
			"Cannot kill task with pid #{task.pid}"
		end
		#task.destroy!
	end
  Task.auto_migrate!
	response['Content-Type'] = 'text/plain'
	"All tasks deleted."
end
