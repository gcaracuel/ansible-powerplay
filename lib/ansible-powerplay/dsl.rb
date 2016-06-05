# -*- coding: utf-8 -*-
module Powerplay
  module DSL
    @@config_stack = [{}]
    @@global_config = {}
    @@planning_queue = []
    
    SPECIAL_PARAMS = [:playbook_directory, :inventory]

    # bump the config stack because we are in a child node context
    def _bump
      @@config_stack.push @@config_stack.last.clone
    end

    # pop the config stack, as we have left the child node context
    def _dip
      @@config_stack.pop
    end

    # Get the current config
    def _config
      @@config_stack.last
    end

    def _global
      @@global_config
    end

    def _verbosity
      _global[:options][:verbose]
    end

    def _enqueue book
      @@planning_queue << book
    end

    def _dequeue
      @@planning_queue.shift
    end

    def _peek
      @@planning_queue.first
    end
    
    def _sneak
      @@planning_queue.last
    end

    # do NOT modify this directly. use the API above.
    def _planning
      @@planning_queue
    end
    
    class Dsl
      attr :config, :type, :desc

      def method_missing(name, *args, &block)
        DSL::_config[name] = args
      end

      def respond_to?(name, include_private = false)
        true
      end

      def configuration(type=:vars, desc=nil, &block)
        @config[type] = DslConfiguration.new(type, desc, &block).config
      end

      def book(type, yaml, desc: nil, plan: :sync, &block)
        @books ||= []
        _enqueue DslBook.new(type, yaml, desc: desc, plan: plan, &block)
      end

      def initialize(type, desc, &ignore)
        @type = type
        @desc = desc
        @config = {}
      end
    end

    class DslConfiguration < Dsl
      def initialize(type, desc, &block)
        super
        instance_eval( &block )
        @config = _config.clone
      end
    end

    # we do allow for noop books
    class DslBook < Dsl
      attr :yaml, :plan

      def initialize(type, yaml, desc: nil, plan: nil, &block)
        super(type, desc, &block)
        @yaml = yaml
        @plan = plan
        _bump
        instance_eval(&block) if block_given?
        @config = _dip
      end

      # Ansible playbook parameters
      def aparams
        config.map{ |k,v|          
          "#{k}=#{v.first}" unless DSL::SPECIAL_PARAMS.member?(k)
        }.compact.join(' ')
      end
    end

    class DslGroup < Dsl
      # The entries here may either be books or groups.
      attr_reader :exec

      def group name, desc = nil, plan = :async, &block
        DslGroup.new(name, desc, plan, &block)
        _enqueue DslBook.new(:noop, nil, plan: @exec) unless @exec == :async or _sneak.type == :sync
      end

      def book(type, yaml, desc: nil, plan: @exec, &block)
        raise ":noop is a reserved book type and cannot be used." if type == :noop
        _enqueue DslBook.new(type, yaml, desc: desc, plan: plan, &block)
      end

      def initialize(type, desc, plan, &block)
        super(type, desc, &block)
        @exec = plan
        _bump
        instance_eval &block 
        @config = _dip
      end
    end

    class DslPlaybook < Dsl
      attr :groups

      def group name, desc = nil, plan = :async, &block
        @groups ||= []
        groups << DslGroup.new(name, desc, plan, &block)
      end

      def initialize (type, desc, &block)
        super
        _bump
        instance_eval( &block )
        @config = _dip
      end
    end

    def configuration(type=:vars, desc=nil, &block)
      _global[type] = DslConfiguration.new(type, desc, &block).config
    end

    def playbooks(type=:vars, desc=nil, &block)
      _global[:playbooks] ||= {}
      _global[:playbooks][type] = DslPlaybook.new type, desc, &block
    end
  end
end
