#
# Author:: Aliasgar Batterywala (aliasgar.batterywala@clogeny.com)
# Copyright:: Copyright (c) 2016 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/azure/helpers/shared'
require 'json'

class ChefClientLogs

  include ChefAzure::Shared

  def initialize(process_thread, start_time, log_location, status_file)
    @chef_client_process_thread = process_thread
    @chef_client_run_start_time = start_time
    @azure_plugin_log_location = log_location
    @azure_status_file = status_file
  end

  def chef_client_log_path
    chef_config
    @chef_config[:log_location] ? @chef_config[:log_location] : "#{@azure_plugin_log_location}/chef-client.log"
  end

  def chef_client_run_exit_status
    if @chef_client_process_thread.value.exitstatus == 0
      'success'    ## successful chef_client_run ##
    else
      'error'      ## unsuccessful chef_client_run ##
    end
  end

  def chef_client_run_complete?
    ## wait for maximum 10 minutes for chef_client_run to complete ##
    chef_client_run_wait_time = ((Time.now - @chef_client_run_start_time) / 60).round
    if @chef_client_process_thread.alive? && chef_client_run_wait_time <= 10
      chef_client_run_complete?
    end
    !@chef_client_process_thread.alive?
  end

  def write_chef_client_logs(sub_status)
    retries = 3
    begin
      ## read azure_status_file to preserve its existing contents ##
      status_file_contents = JSON.parse(File.read(@azure_status_file))

      ## append chef_client_run logs into the substatus field of azure_status_file ##
      status_file_contents[0]["status"]["substatus"] = [{
        "name" => "Chef Extension Handler",
        "status" => "#{sub_status[:status]}",
        "code" => 0,
        "formattedMessage" => {
          "lang" => "en-US",
          "message" => "#{sub_status[:message]}"
        }
      }]

      # Write the new status
      File.open(@azure_status_file, 'w') do |file|
        file.write(status_file_contents.to_json)
      end
    rescue Errno::EACCES => e
      puts "{#{e.message}} - Retrying in 2 secs..."
      if not (retries -= 1).zero?
        sleep 2
        retry
      end
    end
  end

  def chef_client_logs
    ## 'transitioning' status depicts that chef_client_run is still going on and
    ## it exceeded maximum wait time limit of 10 minutes, whereas 'success' or 'error'
    ## status message depends on exit status of chef_client_run
    sub_status = { :status => chef_client_run_complete? ? chef_client_run_exit_status : 'transitioning',
      :message => File.read(chef_client_log_path) }

    write_chef_client_logs(sub_status)
  end
end

logs = ChefClientLogs.new(ARGV[0], ARGV[1], ARGV[2], ARGV[3])
logs.chef_client_logs
