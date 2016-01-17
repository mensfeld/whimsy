#
# Overall monitor class is responsible for loading and running each
# monitor in the `monitors` directory, collecting and normalizing the
# results and outputting it as JSON.
#

require 'json'
require 'time'

class Monitor
  # match http://getbootstrap.com/components/#alerts
  LEVELS = %w(success info warning danger)

  attr_reader :status

  def initialize
    status_file = File.expand_path('../status.json', __FILE__)
    File.open(status_file, File::RDWR|File::CREAT, 0644) do |file|
      # lock the file
      mtime = File.exist?(status_file) ? File.mtime(status_file) : Time.at(0)
      file.flock(File::LOCK_EX)

      # fetch previous status
      baseline = JSON.parse(file.read) rescue {}
      baseline['data'] = {} unless baseline['data'].instance_of? Hash

      # If status was updated while waiting for the lock, use the new status
      if not File.exist?(status_file) or mtime != File.mtime(status_file)
        @status = baseline
        return
      end

      # invoke each monitor, collecting status from each
      newstatus = {}
      self.class.singleton_methods.sort.each do |method|
        # invoke method to determine current status
        begin
          previous = baseline[method] || {mtime: Time.at(0).gmtime.iso8601}
          status = Monitor.send(method, previous) || previous

          # convert non-hashes in proper statuses
          if not status.instance_of? Hash
            if status.instance_of? String or status.instance_of? Array
              status = {data: status}
            else
              status = {level: 'danger', data: status.inspect}
            end
          end
        rescue Exception => e
          status = {
            level: 'danger', 
            data: {
              exception: {
                level: 'danger', 
                text: e.inspect, 
                data: e.backtrace
              }
            }
          }
        end

        # default mtime to now
        status['mtime'] ||= Time.now.gmtime.iso8601 if status.instance_of? Hash

        # update baseline
        newstatus[method] = status
      end

      # normalize status
      @status = normalize(data: newstatus)

      # update results
      file.rewind
      file.write JSON.pretty_generate(@status)
      file.flush
      file.truncate(file.pos)
    end
  end

  ISSUE_TYPE = {
    'success' => 'successes',
    'info'    => 'updates',
    'warning' => 'warnings',
    'danger'  => 'issues'
  }

  ISSUE_TYPE.default = 'problems'

  # default fields, and propagate status 'upwards'
  def normalize(status)
    # convert symbols to strings
    status.keys.each do |key|
      status[key.to_s] = status.delete(key) if key.instance_of? Symbol
    end

    # normalize data
    if status['data'].instance_of? Hash
      # recursively normalize the data structure
      status['data'].values.each {|value| normalize(value)}
    elsif not status['data']
      # default data
      status['data'] = 'missing'
      status['level'] ||= 'danger'
    end

    # normalize level (filling in title when this occurs)
    if status['level']
      if not LEVELS.include? status['level']
        status['title'] ||= "invalid status: #{status['level'].inspect}"
        status['level'] = 'danger'
      end
    else
      if status['data'].instance_of? Hash
        # find the values with the highest status level
        highest = status['data'].
          group_by {|key, value| LEVELS.index(value['level']) || 9}.max

        # adopt that level
        status['level'] = LEVELS[highest.first] || 'danger'

        group = highest.last
        if group.length > 1
          # indicate the number of item with that status
          status['title'] = "#{group.length} #{ISSUE_TYPE[status['level']]}"
        else
          # indicate the item with the problem
          key, value = group.first
          if value['title']
            status['title'] ||= "#{key} #{value['title']}"
          else
            status['title'] ||= "#{key} #{value['data'].inspect}"
          end
        end
      else
        # default level
        status['level'] ||= 'success'
      end
    end

    status
  end
end

# load the monitors
Dir[File.expand_path('../monitors/*.rb', __FILE__)].each do |monitor|
  require monitor
end

# for debugging purposes
if __FILE__ == $0
  puts JSON.pretty_generate(Monitor.new.status)
end
