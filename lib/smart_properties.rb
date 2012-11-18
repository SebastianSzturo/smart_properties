##
# {SmartProperties} can be used to easily build more full-fledged accessors
# for standard Ruby classes. In contrast to regular accessors,
# {SmartProperties} support validation and conversion of input data, as well
# as, the specification of default values. Additionally, individual
# {SmartProperties} can be marked as required. This causes the runtime to
# throw an +ArgumentError+ whenever a required property has not been
# specified.
#
# In order to use {SmartProperties}, simply include the {SmartProperties}
# module and use the {ClassMethods#property} method to define properties.
#
# @see ClassMethods#property
#   More information on how to configure properties
#
# @example Definition of a property that makes use of all {SmartProperties} features.
#
#  property :language_code, :accepts => [:de, :en],
#                           :converts => :to_sym,
#                           :default  => :de,
#                           :required => true
#
module SmartProperties

  VERSION = "1.1.0"

  class Property

    attr_reader :name
    attr_reader :converter
    attr_reader :accepter

    def initialize(name, attrs = {})
      attrs = attrs.dup

      @name      = name.to_sym
      @default   = attrs.delete(:default)
      @converter = attrs.delete(:converts)
      @accepter  = attrs.delete(:accepts)
      @required  = !!attrs.delete(:required)

      unless attrs.empty?
        raise ArgumentError, "SmartProperties do not support the following configuration options: #{attrs.keys.join(', ')}."
      end
    end

    def required=(value)
      @required = !!value
    end

    def required?
      @required
    end

    def convert(value, scope)
      return value unless converter

      if converter.respond_to?(:call)
        scope.instance_exec(value, &converter)
      else
        begin
          value.send(:"#{converter}")
        rescue NoMethodError
          raise ArgumentError, "#{value.class.name} does not respond to ##{converter}"
        end
      end
    end

    def default(scope)
      @default.kind_of?(Proc) ? scope.instance_exec(&@default) : @default
    end

    def accepts?(value, scope)
      return true unless value
      return true unless accepter

      if accepter.kind_of?(Enumerable)
        accepter.include?(value)
      elsif !accepter.kind_of?(Proc)
        accepter === value
      else
        !!scope.instance_exec(value, &accepter)
      end
    end

    def prepare(value, scope)
      if required? && value.nil?
        raise ArgumentError, "#{scope.class.name} requires the property #{self.name} to be set"
      end

      value = convert(value, scope) unless value.nil?

      unless accepts?(value, scope)
        raise ArgumentError, "#{scope.class.name} does not accept #{value.inspect} as value for the property #{self.name}"
      end

      @value = value
    end

    def define(klass)
      property = self

      scope = klass.instance_variable_get(:"@_smart_properties_method_scope") || begin
        m = Module.new
        klass.send(:include, m)
        klass.instance_variable_set(:"@_smart_properties_method_scope", m)
        m
      end

      scope.send(:attr_reader, name)
      scope.send(:define_method, :"#{name}=") do |value|
        instance_variable_set("@#{property.name}", property.prepare(value, self))
      end
    end

  end

  ##
  # {AttributeBuilder} is a singleton object that builds and keeps track of
  # annonymous class that can be used to build attribute hashes for smart
  # property enabled classes.
  #
  class << (AttributeBuilder = Object.new)

    ##
    # Returns an attribute builder for a given klass. If the attribute builder
    # does not exist yet, it is created.
    #
    # @return [Class]
    #
    def [](klass)
      store.fetch(klass) { new(property_names_for(klass)) }
    end

    ##
    # Constructs a hash of attributes for a smart property enabled class using
    # the instructions provided by the block.
    #
    # @return [Hash<String, Object>] Hash of attributes
    #
    def build_attributes_for(klass, &block)
      block.nil? ? {} : self[klass].new(&block).to_hash
    end

    ##
    # Returns the name of this singleton object.
    #
    # @return String
    #
    def inspect
      "AttributeBuilder"
    end
    alias :to_s :inspect

    ##
    # Creates a new anonymous class that can act as an attribute builder.
    #
    # @return [Class]
    #
    def new(fields)
      Struct.new(*fields) do
        def initialize(*args, &block)
          super
          yield(self) if block
        end

        def to_hash
          Hash[members.zip(entries)]
        end
      end
    end

    private

      def property_names_for(klass)
        klass.properties.keys
      end

      def store
        @store ||= {}
      end

  end

  module ClassMethods

    ##
    # Returns a class's smart properties. This includes the properties that
    # have been defined in the parent classes.
    #
    # @return [Hash<String, Property>] A map of property names to property instances.
    #
    def properties
      @_smart_properties ||= begin
        parent = if self != SmartProperties
          (ancestors[1..-1].find { |klass| klass.ancestors.include?(SmartProperties) && klass != SmartProperties })
        end

        parent ? parent.properties.dup : {}
      end
    end

    ##
    # Defines a new property from a name and a set of options. This results
    # results in creating an accessor that has additional features:
    #
    # 1. Validation of input data by specifiying the +:accepts+ option:
    #    If you use a class as value for this option, the setter will check
    #    if the value it is about to assign is of this type. If you use an
    #    array, the setter will check if the value it is about to assign is
    #    included in this array. Finally, if you specify a block, it will
    #    invoke the block with the value it is about to assign and check if
    #    the block returns a thruthy value, meaning anything but +false+ and
    #    +nil+.
    #
    # 2. Conversion of input data by specifiying the +:converts+ option:
    #    If you use provide a symbol as value for this option, the setter will
    #    invoke this method on the object it is about to assign and take the
    #    result of this call instead. If you provide a block, it will invoke
    #    the block with the value it is about to assign and take the result
    #    of the block instead.
    #
    # 3. Providing a default value by specifiying the +:default+ option.
    #
    # 4. Forcing a property to be present by setting the +:required+ option
    #    to true.
    #
    #
    # @param [Symbol] name the name of the property
    #
    # @param [Hash] options the list of options used to configure the property
    # @option options [Array, Class, Proc] :accepts
    #   specifies how the validation is done
    # @option options [Proc, Symbol] :converts
    #   specifies how the conversion is done
    # @option options :default
    #   specifies the default value of the property
    # @option options [true, false] :required
    #   specifies whether or not this property is required
    #
    # @return [Property] The defined property.
    #
    # @example Definition of a property that makes use of all {SmartProperties} features.
    #
    #  property :language_code, :accepts => [:de, :en],
    #                           :converts => :to_sym,
    #                           :default  => :de,
    #                           :required => true
    #
    def property(name, options = {})
      p = Property.new(name, options)
      p.define(self)

      properties[name] = p
    end
    protected :property

  end

  class << self

    private

      ##
      # Extends the class, which this module is included in, with a property
      # method to define properties.
      #
      # @param [Class] base the class this module is included in
      #
      def included(base)
        base.extend(ClassMethods)
      end

  end

  ##
  # Implements a key-value enabled constructor that acts as default
  # constructor for all {SmartProperties}-enabled classes.
  #
  # @param [Hash] attrs the set of attributes that is used for initialization
  #
  def initialize(attrs = {}, &block)
    attrs ||= {}
    attrs = attrs.merge(AttributeBuilder.build_attributes_for(self.class, &block)) if block

    self.class.properties.each do |_, property|
      value = attrs.key?(property.name) ? attrs.delete(property.name) : property.default(self)
      send(:"#{property.name}=", value)
    end
  end

end
