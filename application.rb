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
  property :created_at, DateTime
  property :finished_at, DateTime
  
  property :resultURI, String, :length => 255
  property :percentageCompleted, Float, :default => 0
  property :hasStatus, String, :default => "Running" #possible states are: "Cancelled", "Completed", "Running", "Error"
  property :title, String, :length => 255
  property :creator, String, :length => 255
  property :description, Text

	is :tree, :order => :created_at
end

DataMapper.auto_upgrade!

get '/?' do
	response['Content-Type'] = 'text/uri-list'
	Task.all.collect{|t| t.uri}.join("\n") + "\n"
end

get '/:id/?' do
  task = Task.get(params[:id])
  halt 404, "Task #{params[:id]} not found." unless task
  
  case request.env['HTTP_ACCEPT']
  #when /text\/x-yaml|\*\/\*/ # matches 'text/x-yaml', '*/*'
  #  response['Content-Type'] = 'text/x-yaml'
	#  task.to_yaml
  when /application\/rdf\+xml|\*\/\*/
    response['Content-Type'] = 'application/rdf+xml'
    owl = OpenTox::Owl.create 'Task', task.uri
    owl.set("creator",task.creator)
    owl.set("title",task.title)
    owl.set("date",task.created_at.to_s)
    owl.set("hasStatus",task.hasStatus)
    owl.set("resultURI",task.resultURI)
    owl.set("percentageCompleted",task.percentageCompleted)
    owl.set("description",task.description)
    owl.rdf
  else
    #TODO implement to_owl 
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
	raise "could not save" unless task.save
	response['Content-Type'] = 'text/uri-list'
	task.uri + "\n"
end

put '/:id/:hasStatus/?' do
  
	task = Task.get(params[:id])
  halt 404,"Task #{params[:id]} not found." unless task
	task.hasStatus = params[:hasStatus] unless /pid|parent/ =~ params[:hasStatus]
  task.description = params[:description] if params[:description]
  
	case params[:hasStatus]
	when "Completed"
		LOGGER.debug "Task " + params[:id].to_s + " completed"
    halt 402,"Param resultURI when completing task" unless params[:resultURI]
    task.resultURI = params[:resultURI]
		task.finished_at = DateTime.now
		task.pid = nil
	when "pid"
		#LOGGER.debug "PID = " + params[:pid].to_s
		task.pid = params[:pid]
	when "parent"
		task.parent = Task.first(:uri => params[:uri])
	when /Cancelled|Error/
		Process.kill(9,task.pid) unless task.pid.nil?
		task.pid = nil
		RestClient.put url_for("/#{task.parent.id}/#{params[:hasStatus]}"),{} unless task.parent.nil? # recursevly kill parent tasks
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
