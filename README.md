Description
===========

Deploy ec2 instances interacting with AWS API, Chef.
Each node will be deployed in a different us-east availability zone (currently there are 5).

The script generates user-data for the ec2 instance with witch we accomplish the following:
 Install and configure chef-client using Opscode public repo.
 Generate chef json attributes file fro the first run.
 Get validation key.
 Initiate first chef-run registering the node with the Chef platform.
 it also does some minor things like dropping additinal keys, setting hostname and installing some pkgs and more.


Usage
=====

Few requirements: 
----------------
1. AWS credentials should be set as Environment variables: "AWSAccessKeyId" and "AWSSecretKey"
https://console.aws.amazon.com/ec2
2. Chef knife have to be installed and configured;
http://wiki.opscode.com/display/chef/Workstation+Setup+for+Mac+OS+X 
3. fog gem
http://fog.io

Then do:
--------

Modify "metadata/myfile.json" to you meet your needs and run:
 
    ./aws_deploy.rb myfile.json

Example is in metadata/data.json

Few things that you might want to change: 

* "number" - # of nodes to bootstrap; 
* "base_hostname" - hostname and chef node name; 
* "ec2-type" - AWS instance type; "run_list" - chef run list. 

http://cloud.ubuntu.com/ami/
some AMIs:
us-east-1       precise amd64   ebs     20120424        ami-a29943cb
us-west-1       precise amd64   ebs     20120424        ami-87712ac2
us-west-2       precise amd64   ebs     20120424        ami-20800c10


TODO
====

* DNS records added for new nodes
* Add ability to place nodes behind an ELB
* Options for storage
* Write something to remove nodes from chef/ec2/dns/ELB.
* Get uniq instance # based on search from chef
* Check if AWS has an instance with the same Name tag
* Make some sort of report, email, send msg to jabber etc.
* Use spice lib to interact with chef API
