# encoding: UTF-8

## Dependencies
#
require "berkszero"
require "fileutils"
require "optparse"
require "open3"


## CLI tools for BerksZero
#
module BerksZero
  module CLI
    module_function

    ### Default command line arguments
    #
    def options
      { :host      => { :args    => ["-H", "--host HOST", "Host to bind to"],
                        :default => BerksZero.ipaddress },
        :port      => { :args    => ["-p", "--port PORT", "Port to listen on"],
                        :default => "4000" },
        :log_level => { :args    => ["-l",
                                     "--log-level LEVEL",
                                     "Set the output log level"],
                        :default => "info" } }
    end

    ### Parses command line arguments
    #
    def parse_args
      cli = options
      options = BerksZero.options
      ::OptionParser.new do |opts|
        opts.banner = "Usage: bzup [options]"
        cli.map do |opt, ks|
          args = ks[:args]
          args[2] += " (default: #{ks[:default]})" if ks.include?(:default)
          opts.on(*args) { |a| options[opt] = a }
        end
      end.parse!
      options
    end

    def up(opts)
      # setup chef-zero
      BerksZero.berkszero(opts) do |kfile, bjson|
        puts "\e[36mWrote out #{kfile}: \e[0m"
        puts ::File.readlines(kfile)
        puts "\e[36mWrote out #{bjson}: \e[0m"
        puts ::File.readlines(bjson)
      end
    end

    ### Returns all process PIDs matching process_name
    #
    def find_pids(process_name)
      ::Open3.popen3("ps aux") do |_stdin, stdout, _stderr, _wait_thr|
        stdout.readlines.
          reject { |ln| %r{#{process_name}}.match(ln).nil? }.
          map    { |ln| ln.split(" ")[1].to_i }
      end
    end

    ### Deletes files/dirs created by BerksZero
    #
    def cleanup_bz(opts)
      [:berks_dir, :berks_json, :chef_dir, :knife_file].
        map { |k| opts[k] }.
        push(%w{ cookbooks default tmp }.
               map { |d| ::File.join(opts[:berks_dir], d) }).
        push("#{opts[:berks_file]}.lock").
        flatten.
        each { |f| ::FileUtils.rm_rf f }
    end

    ### Kills chef-zero and cleans up BerksZero stuff
    #
    def down(opts)
      pids = find_pids("chef-zero")

      # kill all chef-zero PIDs if any found
      if pids.empty?
        puts "\e[33mNo processes found matching /chef-zero/\e[00m"
      else
        puts "\e[31mKilling all /chef-zero/\e[00m"
        pids.each do |pid|
          puts "  \e[31mKilling #{pid}\e[00m"
          ::Process.kill("HUP", pid)
        end
      end

      cleanup_bz(opts)
    end
  end
end
