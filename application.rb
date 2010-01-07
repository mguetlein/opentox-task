require 'rubygems'
gem 'opentox-ruby-api-wrapper', '~>1.2'
require 'opentox-ruby-api-wrapper'
require 'dm-core'
require 'dm-serializer'
require 'dm-timestamps'

set :lock, true

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/task.sqlite3")

class Task
	include DataMapper::Resource
	property :id, Serial
	property :uri, String
	property :resource, String
	property :status, Text
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
	task = Task.new :resource => params[:resource_uri], :status => "started"
	task.save
	task.uri = url_for("/#{task.id}", :full)
	task.save
	task.uri
end

put '/:id/completed' do
	task = Task.get(params[:id])
	task.status = "completed"
	task.finished_at = DateTime.now
	task.save
end

put '/:id/cancel' do
	task = Task.get(params[:id])
	task.status = "cancelled"
	task.save
end

delete '/:id/?' do
	Task.destroy!(params[:id])
end

