require "miasma"

module Miasma
  module Models
    class Orchestration
      # Abstract server
      class Stack < Types::Model

        # Stack states which are valid to apply update plan
        VALID_PLAN_STATES = [
          :create_complete, :update_complete, :update_failed,
          :rollback_complete, :rollback_failed,
        ]

        autoload :Resource, "miasma/models/orchestration/resource"
        autoload :Resources, "miasma/models/orchestration/resources"
        autoload :Event, "miasma/models/orchestration/event"
        autoload :Events, "miasma/models/orchestration/events"

        include Miasma::Utils::Memoization

        # Stack update plan
        class Plan < Types::Data
          attr_reader :stack

          def initialize(stack, args = {})
            @stack = stack
            super args
          end

          class Diff < Types::Data
            attribute :name, String, :required => true
            attribute :current, String, :required => true
            attribute :proposed, String, :required => true
          end

          # Plan item
          class Item < Types::Data
            attribute :name, String, :required => true
            attribute :type, String, :required => true
            attribute :diffs, Diff, :multiple => true
          end

          attribute :add, ItemCollection, :multiple => true
          attribute :remove, ItemCollection, :multiple => true
          attribute :replace, ItemCollection, :multiple => true
          attribute :interrupt, ItemCollection, :multiple => true
          attribute :unavailable, ItemCollection, :multiple => true
          attribute :unknown, ItemCollection, :multiple => true

          # Apply this stack plan
          #
          # @return [Stack]
          def apply!
            if self == stack.plan
              stack.plan_apply
            else
              raise Error::InvalidStackPlan.new "Plan is no longer valid for linked stack."
            end
            stack.reload
          end
        end

        # Stack output
        class Output < Types::Data
          attribute :key, String, :required => true
          attribute :value, String, :required => true
          attribute :description, String

          attr_reader :stack

          def initialize(stack, args = {})
            @stack = stack
            super args
          end
        end

        attribute :name, String, :required => true
        attribute :description, String
        attribute :state, Symbol, :allowed => Orchestration::VALID_RESOURCE_STATES, :coerce => lambda { |v| v.to_sym }
        attribute :outputs, Output, :coerce => lambda { |v, stack| Output.new(stack, v) }, :multiple => true
        attribute :status, String
        attribute :status_reason, String
        attribute :created, Time, :coerce => lambda { |v| Time.parse(v.to_s) }
        attribute :updated, Time, :coerce => lambda { |v| Time.parse(v.to_s) }
        attribute :parameters, Smash, :coerce => lambda { |v| v.to_smash }
        attribute :template, Smash, :depends => :perform_template_load, :coerce => lambda { |v| v = MultiJson.load(v) if v.is_a?(String); v.to_smash }
        attribute :template_url, String
        attribute :template_description, String
        attribute :timeout_in_minutes, Integer
        attribute :tags, Smash, :coerce => lambda { |v| v.to_smash }, :default => Smash.new
        # TODO: This is new in AWS but I like this better for the
        # attribute. For now, keep both but i would like to deprecate
        # out the disable_rollback and provide the same functionality
        # via this attribute.
        attribute :on_failure, String, :allowed => %w(nothing rollback delete), :coerce => lambda { |v| v.to_s.downcase }
        attribute :disable_rollback, [TrueClass, FalseClass]
        attribute :notification_topics, String, :multiple => true
        attribute :capabilities, String, :multiple => true
        attribute :plan, Plan, :depends_on => :perform_template_plan

        on_missing :reload

        # Overload the loader so we can extract resources,
        # events, and outputs
        def load_data(args = {})
          args = args.to_smash
          @resources = (args.delete(:resources) || []).each do |r|
            Resource.new(r)
          end
          @events = (args.delete(:events) || []).each do |e|
            Event.new(e)
          end
          super args
        end

        # Validate the stack template
        #
        # @return [TrueClass]
        # @raises [Miasma::Error::OrchestrationError::InvalidTemplate]
        def validate
          perform_template_validate
        end

        # Apply current plan
        #
        # @return [self]
        def plan_apply
          perform_template_apply
        end

        # Override to scrub custom caches
        #
        # @return [self]
        def reload
          clear_memoizations!
          remove = data.keys.find_all do |k|
            ![:id, :name].include?(k.to_sym)
          end
          remove.each do |k|
            data.delete(k)
          end
          super
        end

        # @return [Events]
        def events
          memoize(:events) do
            Events.new(self)
          end
        end

        # @return [Resources]
        def resources
          memoize(:resources) do
            Resources.new(self)
          end
        end

        # Always perform save. Remove dirty check
        # provided by default.
        def save
          perform_save
        end

        protected

        # Stack is in valid state to generate plan
        #
        # @return [TrueClass, FalseClass]
        def planable?
          VALID_PLAN_STATES.include?(state)
        end

        # Proxy plan action up to the API
        def perform_plan
          if planable?
            api.stack_plan(self)
          else
            raise Error::InvalidPlanState.new "Stack state `#{state}` is not" \
                                              "valid for plan generation"
          end
        end

        # Proxy plan apply action up to the API
        def perform_plan_apply
          api.stack_plan_apply(self)
        end

        # Proxy plan delete action up to the API
        def perform_plan_delete
          api.stack_plan_delete(self)
        end

        # Proxy save action up to the API
        def perform_save
          api.stack_save(self)
        end

        # Proxy reload action up to the API
        def perform_reload
          api.stack_reload(self)
        end

        # Proxy destroy action up to the API
        def perform_destroy
          api.stack_destroy(self)
        end

        # Proxy validate action up to API
        def perform_template_validate
          error = api.stack_template_validate(self)
          if error
            raise Error::OrchestrationError::InvalidTemplate.new(error)
          end
          true
        end

        # Proxy template loading up to the API
        def perform_template_load
          memoize(:template) do
            self.data[:template] = api.stack_template_load(self)
            true
          end
        end
      end
    end
  end
end
