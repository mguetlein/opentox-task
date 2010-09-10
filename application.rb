require 'rubygems'
gem "opentox-ruby-api-wrapper", "= 1.6.2"
require 'opentox-ruby-api-wrapper'
#require "dm-is-tree"

class Task
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
  property :created_at, DateTime
  
  property :finished_at, DateTime
  property :due_to_time, DateTime
  property :taskParameters, String, :length => 1024 
  property :pid, Integer
  
  property :resultURI, String, :length => 255
  property :percentageCompleted, Float, :default => 0
  property :hasStatus, String, :default => "Running" #possible states are: "Cancelled", "Completed", "Running", "Error"
  property :title, String, :length => 255
  property :creator, String, :length => 255
  property :description, Text
end

DataMapper.auto_upgrade!

get '/?' do
	response['Content-Type'] = 'text/uri-list'
	Task.all(params).collect{|t| t.uri}.join("\n") + "\n"
end

get '/:id/?' do
  task = Task.get(params[:id])
  halt 404, "Task '#{params[:id]}' not found." unless task
  
  task_content = {:creator => task.creator, :title => task.title, :date => task.created_at, :hasStatus => task.hasStatus,
   :resultURI => task.resultURI, :percentageCompleted => task.percentageCompleted, :description => task.description,
   :due_to_time => task.due_to_time, :taskParameters => task.taskParameters }
  
  code = task.hasStatus == "Running" ? 202 : 200
  
  case request.env['HTTP_ACCEPT']
  when /application\/x-yaml|\*\/\*/ # matches 'application/x-yaml', '*/*'
    response['Content-Type'] = 'application/x-yaml'
    task_content[:uri] = task.uri
    halt code, task_content.to_yaml
  when /application\/rdf\+xml|\*\/\*/
    response['Content-Type'] = 'application/rdf+xml'
    owl = OpenTox::Owl.create 'Task', task.uri
    task_content.each{ |k,v| owl.set(k.to_s,v)}
    halt code, owl.rdf
  when /text\/uri\-list/
    response['Content-Type'] = 'text/uri-list'
    halt code, task.resultURI
  else
    halt 400, "MIME type '"+request.env['HTTP_ACCEPT'].to_s+"' not supported, valid Accept-Headers are \"application/rdf+xml\" and \"application/x-yaml\"."
  end
end

# dynamic access to Task properties
get '/:id/:property/?' do
	response['Content-Type'] = 'text/plain'
  task = Task.get(params[:id])
  halt 404,"Task #{params[:id]} not found." unless task
	eval("task.#{params[:property]}").to_s
end

post '/?' do
  LOGGER.debug "Creating new task with params "+params.inspect
  max_duration = params.delete(:max_duration.to_s) if params.has_key?(:max_duration.to_s)
  task = Task.new(params)
  task.save # needed to create id
  task.uri = url_for("/#{task.id}", :full)
  task.due_to_time = DateTime.parse((Time.parse(task.created_at.to_s) + max_duration.to_f).to_s) if max_duration
  raise "could not save" unless task.save
  response['Content-Type'] = 'text/uri-list'
  task.uri + "\n"
end

put '/:id/:hasStatus/?' do
  
	task = Task.get(params[:id])
  halt 404,"Task #{params[:id]} not found." unless task
	task.hasStatus = params[:hasStatus] unless /pid/ =~ params[:hasStatus]
  task.description = params[:description] if params[:description]
  
	case params[:hasStatus]
	when "Completed"
		LOGGER.debug "Task " + params[:id].to_s + " completed"
    halt 402,"no param resultURI when completing task" unless params[:resultURI]
    task.resultURI = params[:resultURI]
		task.finished_at = DateTime.now
    task.pid = nil
  when "pid"
    task.pid = params[:pid]
	when /Cancelled|Error/
		Process.kill(9,task.pid) unless task.pid.nil?
		task.pid = nil
  else
     halt 402,"Invalid value for hasStatus: '"+params[:hasStatus].to_s+"'"
  end
	
  halt 500,"could not save task" unless task.save
    
end

delete '/:id/?' do
	task = Task.get(params[:id])
  halt 404, "Task #{params[:id]} not found." unless task
	begin
		Process.kill(9,task.pid) unless task.pid.nil?
	rescue
		halt 500,"Cannot kill task with pid #{task.pid}"
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
