require 'rubygems'
gem 'opentox-ruby-api-wrapper', '~>1.2'
require 'opentox-ruby-api-wrapper'
require 'dm-core'
require 'dm-serializer'
require 'dm-timestamps'
require 'dm-types'

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/task.sqlite3")

class Task
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 100
	property :resource, String, :length => 100
	property :status, String, :default => "created"
	property :created_at, DateTime
	property :finished_at, DateTime
end

DataMapper.auto_upgrade!

get '/?' do
	Task.all.collect{|t| t.uri}.join("\n")
end

get '/:id/?' do
	task = Task.get(params[:id])
	task.to_yaml
end

# dynamic access to Task properties
get '/:id/:property/?' do
	task = Task.get(params[:id])
	eval("task.#{params[:property]}").to_s
end

post '/?' do
	task = Task.new
	task.save # needed to create id
	task.uri = url_for("/#{task.id}", :full)
	task.save
	task.uri
end

put '/:id/:status/?' do
	task = Task.get(params[:id])
	task.status = params[:status]
	if params[:status] == "completed"
		task.resource = params[:resource]
		task.finished_at = DateTime.now
	end
	task.save
end

delete '/:id/?' do
	Task.get(params[:id]).destroy!
	"Task #{params[:id]} deleted."
end

delete '/?' do
	Task.all.each do |task|
		task.destroy!
	end
	"All tasks deleted."
end
