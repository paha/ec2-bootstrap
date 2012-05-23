#!/usr/bin/env ruby
#
# Read the README.
#

require 'logger'
require 'erb'
# add Mac compatability
require 'json' unless RUBY_PLATFORM.downcase.include?("darwin")

require 'rubygems'
require 'fog'
require 'chef/knife'
require 'chef/search/query'

# AWS Access and Secret key have to be set as user env variables.
abort "AWS credentials are not found in your environment." unless ENV["AWSAccessKeyId"] and ENV["AWSSecretKey"]

# store user data files and other things in 'data' dir, create it if needed.
@dataDir = File.join( File.dirname(__FILE__), "data")
Dir::mkdir(@dataDir) unless FileTest::directory?(@dataDir)

# read basics out of json
fileName = ARGV[0] || "data.json"
dataFile = File.join("metadata", fileName)
abort "Can't locate data file at #{File.join(Dir::pwd, dataFile)}" unless File.exists?(dataFile)

# logFile = File.join( File.dirname(__FILE__), 'ec2.log' )
logFile = File.join(@dataDir, "ec2.log")
@logger = Logger.new( logFile, 4, 1024000)
@logger.datetime_format = " %a %b %d, %Y %H:%M:%S "
@logger.info( "Begin." )

begin  
  data = JSON.parse( File.read( dataFile ))  
rescue JSON::ParserError
  msg = "Failed to parce json in #{dataFile}."
  @logger.error(msg)
  abort msg
end

# Not checking if templates and multipart assembly script exists
# Generate user-data
def user_data(instance)
  hostname = instance["hostname"]
  # write specific per instance cloud-init config and script files out of erb templates.
  %w(config script).each do |ud|
    e = ERB.new(File.read(File.join('templates', ud + ".erb")))
    outfile = File.join(@dataDir, hostname + "-" + ud)
    File.open(outfile, 'w') {|f| f.write e.result(binding)}
  end

  # files = Hash[*%w{mimeOut script config}.collect {|n| [n, File.join(@dataDir, hostname + "-" + n]}.flatten]
  # files = %w{mimeOut script config}.inject({}) { |f,n| f[n] = File.join(@dataDir, hostname + "-" + n); f}
  mimeOut = File.join(@dataDir, hostname + "-ud")
  script = File.join(@dataDir, hostname + "-script")
    config = File.join(@dataDir, hostname + "-config")
    system("./write-mime-multipart --output=#{mimeOut} #{script}:text/x-shellscript #{config}")
    @logger.info("Generated multipart for #{hostname}")
    return File.read(mimeOut)
end

def make_instance(ec2, instance, talk = true)
  
  new_server = ec2.servers.create(
    :groups 	=> instance["security_group"],
    :flavor_id 	=> instance["ec2-type"],
    :image_id 	=> instance["ec2-ami"],
    # :root_device_type => instance["storage_type"] || "ebs",
    :key_name 	=> instance["key"],
    :user_data	=> instance["userdata"],
    :availability_zone => instance["availability_zone"]
  )

  puts "Starting a new ec2 #{instance["ec2-type"]} instance" if talk
	
  new_server.wait_for { print "."; ready? }

  instance["tags"].each do |k,v|
    server_tag = ec2.tags.create(
      :key	=> k,
      :value	=> v,
      :resource_id => new_server.id
    )
    server_tag.save
  end

  # Add tag to the first/root ebs volume of the instance
  unless instance["storage-type"] == "instance store"
    volume_tag = ec2.tags.create(
      :key	  => "Name",
      :value	  => "vol_" + instance["hostname"].split(".").first,
      :resource_id => new_server.volumes.first.id
    )
    volume_tag.save
  end

  puts	
  puts "Built ec2 instance: #{instance["hostname"]} #{new_server.id} #{new_server.public_ip_address} #{new_server.availability_zone}" if talk
end

# Testing if chef already has node with the same fqdn registered
def check_chef(hostname)
  knife = Chef::Knife.new
  knife.config[:config_file] = File.join(ENV['HOME'], '.chef', 'knife.rb')
  knife.configure_chef
  search_query = Chef::Search::Query.new
  result = search_query.search(:node, "name:#{hostname}")
  
  if result.last > 0
    puts msg = "Chef already has node #{hostname} registered. Skipping"
    @logger.warn(msg)
    return false
  end
  return true
end

def ec2_connect(key = ENV["AWSAccessKeyId"], secret = ENV["AWSSecretKey"]) 
  ec2 = Fog::Compute.new(
    :provider => "aws",
    :aws_access_key_id => key,
    :aws_secret_access_key => secret
  )
end

def get_secUrl(bucket, file, expire = 1200)
  s3 = Fog::Storage::AWS.new(
    :aws_access_key_id => ENV["AWSAccessKeyId"],
    :aws_secret_access_key => ENV["AWSSecretKey"]
  )
	
  return s3.get_object_https_url(
    bucket,
    file,
    Time.now + expire
  )
end

# will work only
def availability_zones(ec2, region)
  r = ec2.describe_availability_zones('region-name' => region).body
  return r["availabilityZoneInfo"].map { |z| z["zoneName"] }
end

# default ec2 instance object
instance = data["default_instance"]
ec2 = ec2_connect

# Get availablity zones for the region and shuffle the array.
zones = availability_zones(ec2, data["region"]).shuffle

# http://blog.piefox.com/2011/07/ec2-availability-zones-and-instance.html
# Not all instance types could be deployed to all availability zones.
no_1a = ["t1.micro", "m1.medium"]
zones.delete("us-east-1a") if no_1a.include?(instance["ec2-type"])

# Make sure we have enough zones to go over
if zones.size < data["number"]
  zones *= data["number"]/zones.size + 1
end
# zones.take(data["number"])

# Generate a secure url to obtain chef validation key, default expire hardcoded in seconds
instance["chef_key_url"] = get_secUrl(data["ec2_backet"], data["validation_file"])

# number of instances to create
data["number"].times do |i|
  instance["hostname"] = data["base_hostname"] + (i + 1).to_s + data["domain"]
  # this is asking for trouble
  instance["userdata"] = user_data(instance)
  # set availablity zone for this node:
  instance["availability_zone"] = zones.shift
  if !check_chef(instance["hostname"])
    puts "This node exist in chef, chef run will fail. Skipping #{instance["hostname"]}." 
    next
  end
  # adding tag for Name
  instance["tags"]["Name"] = instance["hostname"].split(".").first
  # pp instance
  # creating an instance. We could make it multi threaded, but maybe later.
  make_instance(ec2, instance)
  # Do some nice output
end
