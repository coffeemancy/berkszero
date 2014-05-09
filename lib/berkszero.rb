# encoding: UTF-8

require "berkszero/version"

require "berkshelf"
require "erubis"
require "json"
require "open3"
require "openssl"
require "socket"

## Helper functions
#
def green(text)
  puts "\e[32m#{text}\e[0m"
end

def red(text)
  puts "\e[31m#{text}\e[0m"
end

# generates a new pem
def pem
  ::OpenSSL::PKey::RSA.new(2048).to_s
end

## BerksZero
#
# Tool to manage chef-zero with berkshelf and create knife files
# TODO: use chef-zero and berkshelf libraries instead of shell calls?
#
module BerksZero
  # gets the IP address to run chef-zero on
  def ipaddress
    ::Socket.ip_address_list.find { |ip| ip.ipv4_private? }.ip_address
  end

  # construct options Hash
  def options(opts = {})
    # set up paths
    path = opts.fetch(:path, Dir.pwd)
    chef_dir = opts.fetch(:chef_dir, ::File.join(path, ".chef"))
    berks_dir = opts.fetch(:berks_dir, ::File.join(path, ".berkshelf"))
    knife_file = opts.fetch(:knife_file, ::File.join(chef_dir, "knife.rb"))
    berks_json = opts.fetch(:berks_json, ::File.join(berks_dir, "config.json"))

    # return hash
    opts.merge(:chef_dir   => chef_dir,
               :berks_dir  => berks_dir,
               :knife_file => knife_file,
               :berks_json => berks_json,
               :host       => opts.fetch(:host, ipaddress),
               :log_level  => opts.fetch(:log_level, "info"),
               :node_name  => opts.fetch(:node_name, ENV["USER"]),
               :port       => opts.fetch(:port, "4000"))
  end

  # configuration
  def config(opts = options, berks = false)
    chef_dir = opts[:chef_dir]
    chef_server_url = "http://#{opts[:host]}:#{opts[:port]}"
    validation_key = ::File.join(chef_dir, "validation/dummy-validator.pem")
    client_key = ::File.join(chef_dir, "keys/dummy.pem")

    # use validation_key_path for berkshelf, otherwise validation_key
    vkey = "validation_key" + (berks ? "_path" : "")
    { :chef => { :chef_server_url        => chef_server_url,
                 :validation_client_name => "chef-validator",
                 vkey.to_sym             => validation_key,
                 :client_key             => client_key,
                 :node_name              => opts[:node_name] },
      :ssl  => { :verify => true } }
  end

  # knife.rb configuration
  def knife_config(opts = options)
    config(opts)[:chef].merge(:log_level    => ":#{opts[:log_level]}",
                              :log_location => "STDOUT",
                              :cache_type   => "BasicFile")
  end

  # ERB to use for generating knife.rb file
  # this can be monkey-patched to generate a different file
  def knife_erb
    ::File.read("knife.rb.erb")
  end

  # generates a valid knife.rb
  def knife_rb(opts = options)
    cfg = config(opts)[:chef]
    ::Erubis::FastEruby.new(knife_erb).result(:cfg => cfg)
  end

  # writes knife.rb file
  def write_knife_rb(opts = options)
    begin
      knife_file = opts[:knife_file]
      cfg = knife_config(opts)

      # create directory and key directory if they don't exist
      [knife_file, cfg[:client_key], cfg[:validation_key]].
        map { |file| ::File.dirname(file) }.
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
    end
    knife_file
  end

  # writes berkshelf configuration file
  def write_berks_json(opts = options)
    begin
      berks_json = opts[:berks_json]
      cfg = config(opts, true)

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
    end
    berks_json
  end

  # starts chef-zero instance if not currently running
  # FIXME: use ChefZero library instead of popen3
  def start_cz(args)
    Open3.popen3("chef-zero #{args}") do |_stdin, _stdout, stderr, wait_thr|
      errs = stderr.readlines
      if errs.find { |ln| ln =~ /EADDRINUSE/ }.nil?
        green("Chef-zero started on pid: #{wait_thr.pid}")
      else
        red("Chef-zero is already running, not starting a new daemon...")
      end
    end
  end

  # uploads cookbooks using berks
  def upload_cookbooks(opts = options)
    berks_options = { :berksfile => nil,
                      :config => opts.fetch(:berks_json, nil),
                      :debug => false,
                      :force => false,
                      :format => "human",
                      :freeze => true,
                      :halt_on_frozen => false,
                      :no_freeze => false,
                      :quiet => false,
                      :skip_syntax_check => false,
                      :ssl_verify => false,
                      :validate => true }
    begin
      berksfile = Berksfile.from_options(berks_options)
      berksfile.upload([], berks_options)
    rescue Exception => e
      red(e.message)
      red("Failed to upload cookbooks to chef-zero server!")
    end
    green("Uploaded cookbooks to chef-zero server")

    # Open3.popen3("berks upload #{args}") do |stdin, stdout, stderr, wait_thr|
    #   stdout.each do |ln|
    #     puts ln # if ln =~ /Uploading/
    #   end
    #   errs = stderr.readlines
    #   if errs.empty?
    #     green("Uploaded cookbooks to chef-zero server")
    #   else
    #     red(errs)
    #   end
    # end
  end

  def berkszero(opts = options)
    knife_file = write_knife_rb(opts)
    berks_json = write_berks_json(opts)
    m = { :host => "-H", :port => "-p", :log_level => "-l" }
    args = m.reduce("") { |a, e| a + "#{e[1]} #{opts[e[0]]} " } + "-d"
    start_cz(args)
    upload_cookbooks(opts)
    # upload_cookbooks("-c #{berks_json}")
    [knife_file, berks_json]
  end
end
