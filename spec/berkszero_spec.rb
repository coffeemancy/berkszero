# encoding: UTF-8
require "./lib/berkszero.rb"

## BerksZero tests
#
# FIXME: write more specs?
#
describe "BerksZero" do
  # Set up options Hash to test against
  let(:opts) do
    { :chef_dir  => "foo",
      :host      => "localhost",
      :log_level => "debug",
      :node_name => "bar",
      :port      => "10443" }
  end

  ### Test knife.rb rendering
  #
  context "knife.rb" do
    let(:cfg) do
      BerksZero.config(opts)
    end

    it "should create a config :chef Hash for knife.rb" do
      # make sure all options are created correctly
      { :chef_server_url => "http://localhost:10443",
        :client_key      => "foo/keys/dummy.pem",
        :node_name       => "bar",
        :validation_key  => "foo/validation/dummy-validator.pem" }.
        each { |k, v| expect(cfg[:chef][k]).to eq(v) }
    end

    it "should add knife config options to config :chef Hash" do
      knife_cfg = BerksZero.knife_config(opts)
      { :log_level    => ":debug",
        :log_location => "STDOUT" }.
        each { |k, v| expect(knife_cfg[k]).to eq(v) }
    end
  end

  ### Test berkshelf configuration
  #
  context "berkshelf" do
    let(:cfg) do
      BerksZero.config(opts, true)
    end

    it "should disable SSL verification in config function" do
      expect(cfg[:ssl][:verify]).to eq(false)
    end

    #### Berks mode
    #
    # When the `config` function is put in "berks mode", it should use
    # :validation_key_path, instead of :validation_key, so the Berkshelf
    # JSON file can be generated simply from the Hash.
    #
    it "should create :validation_key_path for berks mode" do
      { :validation_key      => nil,
        :validation_key_path => "foo/validation/dummy-validator.pem" }.
        each { |k, v| expect(cfg[:chef].fetch(k, nil)).to eq(v) }
    end
  end
end
