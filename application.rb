require 'rubygems'
gem "opentox-ruby", "~> 0"
require 'opentox-ruby'

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
  
  property :waiting_for, String, :length => 255
  
  property :errorReport, Object

  def metadata
    {
      DC.creator => @creator,
      DC.title => @title,
      DC.date => @created_at,
      OT.hasStatus => @hasStatus,
      OT.resultURI => @resultURI,
      OT.percentageCompleted => @percentageCompleted,
      #text fields are lazy loaded, using member variable can cause description to be nil
      DC.description => description   
      #:due_to_time => @due_to_timer
    }
  end
end

DataMapper.auto_upgrade!

# Get a list of all tasks
# @return [text/uri-list] List of all tasks
get '/?' do
	LOGGER.debug "list all tasks "+params.inspect
  if request.env['HTTP_ACCEPT'] =~ /html/
    response['Content-Type'] = 'text/html'
    OpenTox.text_to_html Task.all(params).collect{|t| t.uri}.join("\n") + "\n"
  else
    response['Content-Type'] = 'text/uri-list'
    Task.all(params).collect{|t| t.uri}.join("\n") + "\n"
  end
end

# Get task representation
# @param [Header] Accept Mime type of accepted representation, may be one of `application/rdf+xml,application/x-yaml,text/uri-list`
# @return [application/rdf+xml,application/x-yaml,text/uri-list] Task representation in requested format, Accept:text/uri-list returns URI of the created resource if task status is "Completed"
get '/:id/?' do
  task = Task.get(params[:id])
  halt 404, "Task '#{params[:id]}' not found." unless task
  code = task.hasStatus == "Running" ? 202 : 200
  
  case request.env['HTTP_ACCEPT']
  when /yaml/ 
    response['Content-Type'] = 'application/x-yaml'
    metadata = task.metadata
    metadata[OT.waitingFor] = task.waiting_for
    metadata[OT.errorReport] = task.errorReport if task.errorReport
    halt code, metadata.to_yaml
  when /html/
    response['Content-Type'] = 'text/html'
    metadata = task.metadata
    metadata[OT.waitingFor] = task.waiting_for
    metadata[OT.errorReport] = task.errorReport if task.errorReport
    halt code, OpenTox.text_to_html(metadata.to_yaml)    
  when /application\/rdf\+xml|\*\/\*/ # matches 'application/x-yaml', '*/*'
    response['Content-Type'] = 'application/rdf+xml'
    LOGGER.debug "requesting task #{params[:id]} in rdf-xml "+task.metadata.inspect
    t = OpenTox::Task.new task.uri
    t.add_metadata task.metadata
    t.add_error_report task.errorReport
    halt t.to_rdfxml
  when /text\/uri\-list/
    response['Content-Type'] = 'text/uri-list'
    # if the task is running return task-uri, as defined in the API
    if code==202 
      halt code, task.uri
    else
      halt code, task.resultURI
    end
  else
    halt 400, "MIME type '"+request.env['HTTP_ACCEPT'].to_s+"' not supported, valid Accept-Headers are \"application/rdf+xml\" and \"application/x-yaml\"."
  end
end


# Get Task properties. Works for
# - /task/id
# - /task/uri
# - /task/created_at
# - /task/finished_at
# - /task/due_to_time
# - /task/pid
# - /task/resultURI
# - /task/percentageCompleted
# - /task/hasStatus
# - /task/title
# - /task/creator
# - /task/description
# @return [String] Task property
get '/:id/:property/?' do
	response['Content-Type'] = 'text/plain'
  task = Task.get(params[:id])
  halt 404,"Task #{params[:id]} not found." unless task
  begin
    eval("task.#{params[:property]}").to_s
  rescue
    halt 404,"Unknown task property #{params[:property]}."
  end
end

# Create a new task
# @param [optional,String] max_duration
# @param [optional,String] pid
# @param [optional,String] resultURI
# @param [optional,String] percentageCompleted
# @param [optional,String] hasStatus
# @param [optional,String] title
# @param [optional,String] creator
# @param [optional,String] description
# @return [text/uri-list] URI for new task
post '/?' do
  LOGGER.debug "Creating new task with params "+params.inspect
  max_duration = params.delete(:max_duration.to_s) if params.has_key?(:max_duration.to_s)
  task = Task.create(params)
  task.uri = url_for("/#{task.id}", :full)
  task.due_to_time = DateTime.parse((Time.parse(task.created_at.to_s) + max_duration.to_f).to_s) if max_duration
  raise "Could not save task #{task.uri}" unless task.save
  response['Content-Type'] = 'text/uri-list'
  task.uri + "\n"
end

# Change task status. Possible URIs are: `
# - /task/Cancelled
# - /task/Completed: requires taskURI argument
# - /task/Running
# - /task/Error
# - /task/pid: requires pid argument
# IMPORTANT NOTE: Rack does not accept empty PUT requests. Please send an empty parameter (e.g. with -d '' for curl) or you will receive a "411 Length Required" error.
# @param [optional, String] resultURI URI of created resource, required for /task/Completed
# @param [optional, String] pid Task PID, required for /task/pid
# @param [optional, String] description Task description
# @param [optional, String] percentageCompleted progress value, can only be set while running
# @return [] nil
put '/:id/:hasStatus/?' do
  
	task = Task.get(params[:id])
  halt 404,"Task #{params[:id]} not found." unless task
	task.hasStatus = params[:hasStatus] unless /pid/ =~ params[:hasStatus]
  task.description = params[:description] if params[:description]
  task.errorReport = YAML.load(params[:errorReport]) if params[:errorReport]
  
	case params[:hasStatus]
	when "Completed"
		LOGGER.debug "Task " + params[:id].to_s + " completed"
    halt 402,"no param resultURI when completing task" unless params[:resultURI]
    task.resultURI = params[:resultURI]
		task.finished_at = DateTime.now
    task.percentageCompleted = 100
    task.pid = nil
  when "pid"
    task.pid = params[:pid]
  when "Running"
    halt 400,"Task cannot be set to running after not running anymore" if task.hasStatus!="Running"
    task.waiting_for = params[:waiting_for] if params.has_key?("waiting_for")
    if params.has_key?("percentageCompleted")
      task.percentageCompleted = params[:percentageCompleted].to_f
      #LOGGER.debug "Task " + params[:id].to_s + " set percentage completed to: "+params[:percentageCompleted].to_s
    end
	when /Cancelled|Error/
    if task.waiting_for and task.waiting_for.uri?
      # try cancelling the child task
      begin
        w = OpenTox::Task.find(task.waiting_for)
        w.cancel if w.running?
      rescue
      end
    end
    LOGGER.debug("Aborting task "+task.uri.to_s)
		Process.kill(9,task.pid) unless task.pid.nil?
		task.pid = nil
  else
     halt 402,"Invalid value for hasStatus: '"+params[:hasStatus].to_s+"'"
  end
	
  halt 500,"could not save task" unless task.save

end

# Delete a task
# @return [text/plain] Status message
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

# Delete all tasks
# @return [text/plain] Status message
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
