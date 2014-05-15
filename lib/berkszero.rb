# encoding: UTF-8

## BerksZero
#
# BerksZero is a tool for workflows involving spinning up multiple transient
# machines (e.g. vagrant, docker) which use a shared, transient Chef server
# instance (e.g. chef-zero). The intention is to be able to use tools made
# for interacting with a Chef server (e.g. knife) during local development,
# as well as for testing features that require a shared Chef server
# (e.g. search).
#
# Berkshelf is used for cookbook dependency management and to upload the
# cookbooks to the chef-zero instance.
#
# For convenience, valid knife.rb (as well as berkshelf configuration files)
# are rendered locally to allow for seamless integration with knife.
#
# Ideally, the ability to use a standalone, shared Chef server would be added
# to test-kitchen, potentionally using BerksZero or making this gem
# deprecated.
#

require "berkszero/version"

### Dependencies
#
require "berkshelf"
require "erubis"
require "json"
require "open3"
require "openssl"
require "socket"

## BerksZero module
#
# A stateless, functional approach is taken, thus, BerksZero is simply a
# module of methods. Unnecessary encapsulation is not used in this
# abstraction.
#
# The primary tool of abstraction is the options Hash which is the first
# argument in many of the method calls, typically `opts`.
#
# TODO: use chef-zero and berkshelf libraries instead of shell calls?
#
module BerksZero
  module_function

  def green(text)
    puts "\e[32m#{text}\e[0m"
  end

  def red(text)
    puts "\e[31m#{text}\e[0m"
  end

  ### Gets the IP address on which to run chef-zero
  #
  def ipaddress
    ::Socket.ip_address_list.find { |ip| ip.ipv4_private? }.ip_address
  end

  ### Generates a new pem
  #
  def pem
    ::OpenSSL::PKey::RSA.new(2048).to_s
  end

  ### Composes an options Hash
  #
  def options(opts = {})
    # set up paths relative to optional `path` argument
    path       = opts.fetch(:path, Dir.pwd)
    berks_file = opts.fetch(:berks_file,
                            ::File.join(path, Berkshelf::DEFAULT_FILENAME))
    # use `local_location` for berks3, default to current dir for berks2
    method = :local_location
    berks_json = opts.fetch(:berks_json,
                            if Berkshelf::Config.method_defined?(method)
                              Berkshelf::Config.send(method)
                            else
                              ::File.join(path, ".berkshelf/config.json")
                            end)
    berks_dir  = opts.fetch(:berks_dir, ::File.dirname(berks_json))
    chef_dir   = opts.fetch(:chef_dir, ::File.join(path, ".chef"))
    knife_file = opts.fetch(:knife_file, ::File.join(chef_dir, "knife.rb"))

    # compose and return options Hash with paths to files and other configs
    opts.merge(:berks_dir  => berks_dir,
               :berks_file => berks_file,
               :berks_json => berks_json,
               :chef_dir   => chef_dir,
               :knife_file => knife_file,
               :host       => opts.fetch(:host, ipaddress),
               :log_level  => opts.fetch(:log_level, "info"),
               :node_name  => opts.fetch(:node_name, ENV["USER"]),
               :port       => opts.fetch(:port, "4000"))
  end

  ### Composes a configuration Hash
  #
  # This method is used to compose a Hash used for knife.rb (for Chef) or
  # config.json (for Berkshelf, if `berks` is `true`).
  #
  def config(opts, berks = false)
    chef_dir        = opts[:chef_dir]
    chef_server_url = "http://#{opts[:host]}:#{opts[:port]}"
    validation_key  = ::File.join(chef_dir, "validation/dummy-validator.pem")
    client_key      = ::File.join(chef_dir, "keys/dummy.pem")

    # use `validation_key_path` for berkshelf, otherwise `validation_key`
    vkey = "validation_key" + (berks ? "_path" : "")

    # compose and return configuration Hash, no SSL for chef-zero
    { :chef => { :chef_server_url        => chef_server_url,
                 :client_key             => client_key,
                 :node_name              => opts[:node_name],
                 :validation_client_name => "chef-validator",
                 vkey.to_sym             => validation_key },
      :ssl  => { :verify                 => false } }
  end

  ### Generates knife.rb configuration Hash
  #
  def knife_config(opts)
    config(opts)[:chef].merge(:log_level    => opts[:log_level],
                              :log_location => "STDOUT",
                              :cache_type   => "BasicFile")
  end

  ### Returns ERB to use for generating knife.rb file
  #
  # This method can be monkey-patched to generate a different file.
  #
  def knife_erb
    <<-EOF
cache_type               "BasicFile"
chef_server_url          "<%= cfg[:chef_server_url] %>"
client_key               "<%= cfg[:client_key] %>"
log_level                :<%= cfg[:log_level] %>
log_location             STDOUT
node_name                "<%= cfg[:node_name] %>"
validation_client_name   "<%= cfg[:validation_client_name] %>"
validation_key           "<%= cfg[:validaton_key] %>"
EOF
  end

  ### Renders valid knife.rb string from ERB
  #
  # A String is returned which is later used to write to knife.rb file.
  #
  def knife_rb(cfg)
    ::Erubis::FastEruby.new(knife_erb).result(:cfg => cfg)
  end

  # writes knife.rb file
  def write_knife_rb(opts, &block)
    begin
      knife_file = opts[:knife_file]
      cfg        = knife_config(opts)

      # create directory and key directory if they don't exist
      [knife_file, cfg[:client_key], cfg[:validation_key]].
        map  { |file| ::File.dirname(file) }.
        each { |dir| ::FileUtils.mkdir_p(dir) }

      # write client/validation PEMs, if don't exist
      [:client_key, :validation_key].each do |k|
        key = cfg[k]
        unless ::File.exist?(key)
          ::File.open(key, "w") { |f| f.puts pem }
          green("Wrote PEM: #{key}")
        end
      end

      # write knife.rb
      ::File.open(knife_file, "w") { |f| f.puts knife_rb(cfg) }
    rescue Exception => e
      red(e.message)
      red("Could not write to file #{knife_file}!")
      raise e
    else
      yield knife_file
    end
  end

  # writes berkshelf configuration file
  def write_berks_json(opts, &block)
    begin
      berks_json = opts[:berks_json]
      cfg        = config(opts, true)

      # create directory if it doesn't exist
      ::FileUtils.mkdir_p(::File.dirname(berks_json))

      # write pretty json to file for berkshelf configuration
      ::File.open(berks_json, "w") do |f|
        f.puts ::JSON.pretty_generate(cfg)
      end
    rescue Exception => e
      red(e.message)
      red("Could not write to file #{berks_json}!")
      raise e
    else
      yield berks_json
    end
  end

  # starts chef-zero instance if not currently running
  # FIXME: use ChefZero library instead of popen3
  def start_cz(args, &block)
    ::Open3.popen3("chef-zero #{args}") do |_stdin, _stdout, stderr, wait_thr|
      errs = stderr.readlines
      if errs.find { |ln| ln =~ /EADDRINUSE/ }.nil?
        green("Chef-zero started on pid: #{wait_thr.pid}")
      else
        red("Chef-zero is already running, not starting a new daemon...")
      end
      yield
    end
  end

  # uploads cookbooks using berks
  def upload_cookbooks(opts)
    cfg = config(opts, true)
    # set up options to support both berks3 and berks2 (ridley)
    berks_options = { :berksfile         => opts.fetch(:berks_file, nil),
                      :client_key        => cfg[:chef][:client_key],
                      :client_name       => cfg[:chef][:node_name],
                      :config            => opts.fetch(:berks_json, nil),
                      :debug             => false,
                      :force             => false,
                      :format            => "human",
                      :freeze            => true,
                      :halt_on_frozen    => false,
                      :no_freeze         => false,
                      :quiet             => false,
                      :server_url        => cfg[:chef][:chef_server_url],
                      :skip_syntax_check => false,
                      :ssl_verify        => cfg[:ssl][:verify],
                      :validate          => true }
    begin
      # use `from_file` for berks2 support, otherwise `from_options`
      method, args = if Berkshelf::Berksfile.method_defined?(:from_options)
                       [:from_options, berks_options]
                     else
                       [:from_file, berks_options[:berksfile]]
                     end
      berksfile = Berkshelf::Berksfile.send(method, args)
      berksfile.upload(berks_options)
    rescue Berkshelf::BerksfileNotFound => e
      red("No Berksfile in current directory!")
      raise e
    rescue Exception => e
      red(e.message)
      red("Failed to upload cookbooks to chef-zero server!")
      raise e
    else
      green("Uploaded cookbooks to chef-zero server")
    end
  end

  def berkszero(opts, &block)
    write_knife_rb(opts) do |knife_file|
      write_berks_json(opts) do |berks_json|
        yield [knife_file, berks_json]
        m = { :host => "-H", :port => "-p", :log_level => "-l" }
        args = m.reduce("") { |a, e| a + "#{e[1]} #{opts[e[0]]} " } + "-d"
        start_cz(args) do
          upload_cookbooks(opts)
        end
      end
    end
  end
end
