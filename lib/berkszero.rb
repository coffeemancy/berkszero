require "berkszero/version"

require "json"
require "open3"
require "openssl"
require "socket"

def green(text)
  puts "\e[32m#{text}\e[0m"
end

def red(text)
  puts "\e[31m#{text}\e[0m"
end

## BerksZero
#
# Hack to manage chef-zero with berkshelf and create knife files
# TODO: use chef-zero and berkshelf libraries instead of shell calls
#
module BerksZero
  # gets the IP address to run chef-zero on
  def self.ipaddress
    ::Socket.ip_address_list.find { |ip| ip.ipv4_private? }.ip_address
  end

  # provides CLI arguments
  def self.cli
    { :host => {  :args => ["-H", "--host HOST", "Host to bind to"],
                  :default => ipaddress },
      :port => {  :args => ["-p", "--port PORT", "Port to listen on"],
                  :default => "4000" },
      :log_level => { :args => ["-l",
                                "--log-level LEVEL",
                                "Set the output log level"],
                      :default => "info" } }
  end

  # default options to use on CLI
  def self.default_options
    cli.map { |opt, ks| { opt => ks[:default] } }.reduce({}, :merge)
  end

  @cwd = Dir.pwd
  @chef_dir = ::File.join(@cwd, ".chef")
  @berks_dir = ::File.join(@cwd, ".berkshelf")
  @knife_file = ::File.join(@chef_dir, "knife.rb")
  @berks_json = ::File.join(@berks_dir, "config.json")

  # determines URL to use for chef-zero server
  def self.chef_server_url(opts)
    "http://#{opts[:host]}:#{opts[:port]}"
  end

  # yields path to chef file based on chef directory
  def self.chef_file(file)
    ::File.join(@chef_dir, file)
  end

  # configuration
  def self.config(opts, berks = false)
    vkey = "validation_key" + (berks ? "_path" : "")
    { :chef => { :chef_server_url => chef_server_url(opts),
                 :validation_client_name => "chef-validator",
                 vkey.to_sym => chef_file("validation/dummy-validator.pem"),
                 :client_key => chef_file("keys/dummy.pem"),
                 :node_name => ENV["USER"] },
      :ssl => { :verify => true } }
  end

  # knife.rb configuration
  def self.knife_config(opts)
    config(opts)[:chef].merge(
      :log_level => ":#{opts[:log_level]}",
      :log_location => "STDOUT",
      :cache_type => "BasicFile")
  end

  def self.berks_config(opts)
    config(opts, true)
  end

  # generates a new pem
  def self.pem
    OpenSSL::PKey::RSA.new(2048).to_s
  end

  # generates a valid knife.rb
  def self.knife_rb(cfg)
    cfg.map do |k, v|
      # HACK: fix for keys that shouldn't be quoted
      unquote_keys = [:log_location, :log_level]
      unquote_keys.include?(k) ? "#{k} #{v}" : "#{k} \"#{v}\""
    end
  end

  def self.gen_berks_json(cfg)
    ::JSON.pretty_generate(cfg)
  end

  def self.with_knife_rb(opts, &block)
    begin
      cfg = knife_config(opts)
      # create directory and key directory if they don't exist
      [@knife_file, cfg[:client_key], cfg[:validation_key]].
        map { |file| ::File.dirname(file) }.
        each { |dir| ::FileUtils.mkdir_p(dir) }
      # write client/validation PEMs, if don't exist
      [cfg[:client_key], cfg[:validation_key]].each do |key|
        unless ::File.exist?(key)
          ::File.open(key, "w") { |f| f.puts pem }
          green("Wrote PEM: #{key}")
        end
      end
      # write knife.rb
      ::File.open(@knife_file, "w") { |f| f.puts knife_rb(cfg) }
      yield @knife_file, cfg
    rescue Exception => e
      red(e.message)
      red("Could not write to file #{@knife_file}!")
      raise e
    end
  end

  def self.with_berks_json(opts, &block)
    begin
      cfg = berks_config(opts)
      # create directory if it doesn't exist
      ::FileUtils.mkdir_p(::File.dirname(@berks_json))
      ::File.open(@berks_json, "w") { |f| f.puts gen_berks_json(cfg) }
      yield @berks_json, cfg
    rescue Exception => e
      red(e.message)
      red("Could not write to file #{@berks_json}!")
      raise e
    end
  end

  def self.start_cz(args)
    Open3.popen3("chef-zero #{args}") do |stdin, stdout, stderr, wait_thr|
      errs = stderr.readlines
      if errs.find { |ln| ln =~ /EADDRINUSE/ }.nil?
        green("Chef-zero started on pid: #{wait_thr.pid}")
      else
        red("Chef-zero is already running, not starting a new daemon...")
      end
    end
  end

  def self.upload_cookbooks(args)
    Open3.popen3("berks upload #{args}") do |stdin, stdout, stderr, wait_thr|
      stdout.each do |ln|
        puts ln # if ln =~ /Uploading/
      end
      errs = stderr.readlines
      if errs.empty?
        green("Uploaded cookbooks to chef-zero server")
      else
        red(errs)
      end
    end
  end

  def self.with_cz(opts = nil, &block)
    opts = default_options if opts.nil?
    with_knife_rb(opts) do |knife_file, knife_config|
      with_berks_json(opts) do |berks_json, berks_config|
        m = { :host => "-H", :port => "-p", :log_level => "-l" }
        args = m.reduce("") { |a, e| a + "#{e[1]} #{opts[e[0]]} " } + "-d"
        start_cz(args)
        upload_cookbooks("-c #{berks_json}")
        yield knife_file, knife_config, berks_json, berks_config
      end
    end
  end
end
