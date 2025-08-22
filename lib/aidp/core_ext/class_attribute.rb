# frozen_string_literal: true

module Aidp
  module CoreExt
    module ClassAttribute
      def class_attribute(*attrs)
        attrs.each do |name|
          # Define class instance variable
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            @#{name} = nil

            def self.#{name}
              return @#{name} if defined?(@#{name})
              return superclass.#{name} if superclass.respond_to?(:#{name})
              nil
            end

            def self.#{name}=(val)
              @#{name} = val
            end

            def #{name}
              self.class.#{name}
            end

            def #{name}=(val)
              raise "#{name} is a class attribute, cannot be set on instance"
            end
          RUBY
        end
      end
    end
  end
end

Class.include Aidp::CoreExt::ClassAttribute
