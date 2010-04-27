require 'rubygems'
gem 'opentox-ruby-api-wrapper', '= 1.4.0'
require 'opentox-ruby-api-wrapper'
require "dm-is-tree"

LOGGER.progname = File.expand_path(__FILE__) 

class Task
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
  property :created_at, DateTime
  
  property :finished_at, DateTime
  property :due_to_time, DateTime
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
	Task.all.collect{|t| t.uri}.join("\n") + "\n"
end

get '/:id/?' do
  task = Task.get(params[:id])
  task_content = {:creator => task.creator, :title => task.title, :date => task.created_at.to_s, :hasStatus => task.hasStatus,
   :resultURI => task.resultURI, :percentageCompleted => task.percentageCompleted, :description => task.description,
   :due_to_time => task.due_to_time.to_s}
  
  halt 404, "Task #{params[:id]} not found." unless task
  
  case request.env['HTTP_ACCEPT']
  when /text\/x-yaml|\*\/\*/ # matches 'text/x-yaml', '*/*'
    response['Content-Type'] = 'text/x-yaml'
    task_content[:uri] = task.uri
	  task_content.to_yaml
  when /application\/rdf\+xml|\*\/\*/
    response['Content-Type'] = 'application/rdf+xml'
    owl = OpenTox::Owl.create 'Task', task.uri
    task_content.each{ |k,v| owl.set(k.to_s,v)}
    owl.rdf
  else
    halt 400, "MIME type '"+request.env['HTTP_ACCEPT'].to_s+"' not supported, valid Accept-Headers are \"application/rdf+xml\" and \"text/x-yaml\"."
  end
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
  task.due_to_time = DateTime.parse((Time.parse(task.created_at.to_s) + params[:max_duration].to_f).to_s) if params[:max_duration]
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
