module Frequent
  VERSION = 0.1

  ProbeNameError = Class.new(StandardError)

  def self.instrument(name)
    probe = Frequent::Probe.new(name)
    probes[name] = probe
    Frequent::Deferred.enable! unless probe.enabled?
    if block_given?
      yield
      probe.disable!
      probes.delete(name)
    end
    probe
  end

  def self.constantize(name)
    names = name.split('::')
    names.shift if names.first == ''
    constant = Object
    until names.empty?
      n = names.shift
      return nil unless constant.const_defined?(n)
      constant = constant.const_get(n, false)
    end
    constant
  end

  def self.probes
    @probes ||= {}
  end
end

module Frequent
  class Probe
    attr_reader :name, :calls, :class_name, :method_name, :original_implementation
    alias_method :to_s, :name

    def initialize(name)
      @calls = 0
      @name = name
      @enabled = false
      parse_name(name)
      enable! if ready?
    end

    def increment
      @calls += 1
    end

    def enabled?
      @enabled
    end

    def ready?
      !enabled? && target_defined?
    end

    def method_owner
      owner = Frequent.constantize(class_name)
      return unless owner
      @type == :instance ? owner : owner.singleton_class
    end

    def target_defined?
      owner = method_owner
      owner && (
        owner.method_defined?(method_name) ||
        owner.private_instance_methods.include?(method_name)
      )
    end

    def enable!
      unless @enabling
        @enabling = true
        @original_implementation = method_owner.instance_method(method_name)
        probe = self
        aliased_name = self.aliased_name
        method_owner.class_eval do
          alias_method aliased_name, probe.method_name
          define_method(probe.method_name) do |*args, &blk|
            probe.increment
            send(aliased_name, *args, &blk)
          end
        end
        @enabled = true
        @enabling = false
      end
    end

    def disable!
      if enabled?
        probe = self
        method_owner.class_eval do
          define_method(probe.method_name, probe.original_implementation)
          remove_method(probe.aliased_name)
        end
      end
    end

    def aliased_name
      "__frequent_original_#{method_name}".to_sym
    end

    def parse_name(name)
      md = name.match(/(.*)(\.|\#)(.*)/)
      raise ProbeNameError.new("Failed to parse probe name '#{name}'") unless md
      class_name, sep, method_name = md[1..3]
      @class_name = class_name
      @type = (sep == '#') ? :instance : :class
      @method_name = method_name.to_sym
    end
  end
end

module Frequent
  module Deferred
    def self.place_by_name(name)
      p = Frequent.probes[name]
      p.enable! if p && p.ready?
    end

    def self.enable!
      return if @enabled
      ::Module.class_eval do
        def method_added(m)
          Frequent::Deferred.place_by_name("#{self}##{m}")
        end

        def singleton_method_added(m)
          Frequent::Deferred.place_by_name("#{self}.#{m}")
        end

        def included(host)
          Frequent.probes.values.select(&:ready?).each(&:enable!)
        end
      end
      @enabled = true
    end
  end
end

if ENV['COUNT_CALLS_TO']
  probe = Frequent.instrument(ENV['COUNT_CALLS_TO'])
  at_exit { puts "#{probe} called #{probe.calls} times" }
end