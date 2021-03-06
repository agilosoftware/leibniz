require 'pry'
require 'leibniz/version'
require 'kitchen'
require 'forwardable'
require 'ipaddr'

module Kitchen
  class Config
    def new_logger(suite, platform, index)
      name = instance_name(suite, platform)
      Logger.new(
                 :color    => Color::COLORS[index % Color::COLORS.size].to_sym,
                 :logdev   => File.join(log_root, "#{name}.log"),
                 :level    => Util.to_logger_level(self.log_level),
                 :progname => name
                 )
    end
  end
end

module Leibniz

  def self.build(specification)
    leibniz_yaml = YAML.load_file(".leibniz.yml")
    loader = KitchenLoader.new(specification, leibniz_yaml)
    config = Kitchen::Config.new(:loader => loader)
    Infrastructure.new(config.instances)
  end

  class Infrastructure

    def initialize(instances)
      @nodes = Hash.new
      instances.each do |instance|
        @nodes[instance.name.sub(/^leibniz-/, '')] = Node.new(instance)
      end
    end

    def [](name)
      @nodes[name]
    end

    def converge
      @nodes.each_pair { |name, node| node.converge }
    end

    def destroy
      @nodes.each_pair { |name, node| node.destroy }
    end

  end

  class Node

    extend Forwardable

    def_delegators :@instance, :create, :converge, :setup, :verify, :destroy, :test

    def initialize(instance)
      @instance = instance
    end
 
    def ip
      instance.driver[:ipaddress]
    end

    private

    attr_reader :instance
  end

  class KitchenLoader

    def initialize(specification, config)
      @config = config
      @last_octet = @config['last_octet']
      @platforms = specification.hashes.map do |spec|
        create_platform(spec)
      end
      @suites = specification.hashes.map do |spec|
        create_suite(spec)
      end
    end

    def read
      {
        :driver_plugin => @config['driver']['name'],
        :platforms => platforms,
        :suites => suites
      }
    end

    private

    attr_reader :platforms, :suites

    def create_suite(spec)
      suite = Hash.new
      suite[:name] = @config['suites'].first['name']
      suite[:provisioner] = @config['provisioner'] || "chef_solo"
      suite[:run_list] = @config['suites'].first['run_list']
      suite[:data_bags_path] = @config['suites'].first['data_bags_path']
      suite
    end


    def create_platform(spec)
      distro = "#{spec['Operating System']}-#{spec['Version']}"
      ipaddress = IPAddr.new(@config['network']).succ.succ.to_s
      platform = Hash.new
      platform[:name] = spec["Server Name"]
      platform[:driver_config] = Hash.new
      platform[:driver_config][:box] = "opscode-#{distro}"
      platform[:driver_config][:box_url] = "https://opscode-vm-bento.s3.amazonaws.com/vagrant/virtualbox/opscode_#{distro}_chef-provisionerless.box"
      platform[:driver_config][:network] = [["private_network", {:ip => ipaddress}]]
      platform[:driver_config][:require_chef_omnibus] = spec["Chef Version"] || true
      platform[:driver_config][:customize] = Hash.new
      customize_params = @config['driver']['customize']
      customize_params.each { |custom_value|
        platform[:driver_config][:customize][custom_value[0]] = custom_value[1]
      }
      platform[:driver_config][:ipaddress] = ipaddress
      platform[:run_list] = spec["Run List"].split(",")
      platform
    end
  end
end

