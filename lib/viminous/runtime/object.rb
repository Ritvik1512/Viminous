module viminous
  module Runtime
    def self.runtime_binding
      binding
    end

    class Exception < ::Exception
    end

    class TypeError < Exception
    end

    module Utils
      def self.ToString(object)
        object.to_s
      end

      def self.ToBoolean(object)
        case object
        when Numeric
          object != 0
        when String
          !object.empty?
        when undefined, nil, false
          false
        else
          true
        end
      end

      def self.logical_not(val)
        !ToBoolean(val)
      end

      def self.brackets(object, name)
        name = ToString(name)

        if object.is_a?(Object)
          object.get(name)
        else
          object.send(name)
        end
      end

      def self.call_with(function, this, *args)
        if function.is_a?(Object) && function.respond_to?(:call_with)
          function.call_with(this, *args)
        else
          # TODO: Use proper JS error semantics
          # TODO: Include the variable name in the error (Chrome: Property 'a' of object #<Object> is not a function)
          raise TypeError, "#{function} is not a function"
        end
      end

      def self.typeof(resolve, name)
        if resolve == undefined
          "undefined"
        else
          val = resolve ? resolve.get(name) : name

          # TODO: Deal with host objects
          case val
          when undefined
            "undefined"
          when nil
            "object"
          when TrueClass, FalseClass
            "boolean"
          when Numeric
            "number"
          when String
            "string"
          when Function
            "function"
          else
            "object"
          end
        end
      end
    end

    # Object protocol:
    #
    # get(name<Symbol>)        => object
    # get_index(index<Fixnum>) => object
    # put(name<Symbol>, object<Object>)
    #

    class Object < Rubinius::LookupTable
      attr_accessor :prototype, :js_class

      def self.with_constructor(constructor)
        object = new
        object.prototype = constructor.get(:prototype)
        constructor.call_with(object)
        object
      end

      dynamic_method(:undefined) do |g|
        g.push_undef
        g.ret
      end

      def function(name, block=name)
        if block.is_a?(Symbol)
          block = method(block).executable
        else
          block = block.code
        end

        self[name] = Function.new(name, block)
      end

      def to_hash
        Hash[*keys.zip(values).flatten]
      end

      def inspect
        "#<#{js_class} #{object_id.to_s(16)} #{to_hash.inspect}>"
      end

      def get(name)
        if self.key?(name)
          self[name]
        elsif proto = prototype
          proto.get(name)
        else
          undefined
        end
      end

      def get_index(index)
        get(Utils.ToString(index))
      end

      def put(name, object, throw=false)
        self[name] = object
      end

      def literal_put(name, object)
        put(name, object)

        # this method is called repeatedly to create new
        # properties for a literal. Return self so we
        # can just call literal_put again without
        # having to make sure the object we're creating
        # is on the stack using bytecode. 
        self
      end

      def can_put?(name)
        true
      end

      def has_property?(name)
        if result = key?(name)
          result
        elsif proto = prototype
          proto.has_property?(name)
        else
          false
        end
      end

      def delete_property(name)
        delete(name)
      end

      def default_value(hint)
        # TODO: This returns stuff like [object Object] which
        # is used by implementations to determine the true type
      end

      def self.empty_object
        obj            = allocate
        obj.prototype  = OBJECT_PROTOTYPE
        obj.js_class   = "Object"
        obj.extensible = true
      end
    end

    ARRAY_PROTOTYPE    = Runtime::Object.new

    class Array < Object
      thunk_method :prototype, ARRAY_PROTOTYPE
      thunk_method :js_class, "Array"
      thunk_method :extensible, true

      def initialize(array)
        @array = array
      end

      def get_index(index)
        if index >= @array.size
          undefined
        else
          @array[index]
        end
      end

      def to_a
        @array
      end
    end

    class Window < Object
      def initialize
        function :p
      end
    end

    class FunctionPrototype < Object
      def initialize
        function :call
      end

      def call(this, *args)
        call_with(this, *args)
      end
    end

    class Function < Object
      def self.for_block(name=:anonymous, &block)
        new(name, block.block.code)
      end

      def initialize(name, executable)
        @name = name

        # created from compiled code
        if executable.is_a?(Rubinius::BlockEnvironment)
          @executable = executable.code

        # created directly from Ruby code (host objects)
        else
          @executable = executable
        end
      end

      def call(*args)
        @executable.invoke(@name, @executable.scope.module, JS_WINDOW, args, nil)
      end

      def call_with(this, *args)
        @executable.invoke(@name, @executable.scope.module, this, args, nil)
      end
    end

    FUNCTION_PROTOTYPE = FunctionPrototype.new

    class Function
      thunk_method :prototype, FUNCTION_PROTOTYPE
      thunk_method :js_class, "Function"
    end

    class ObjectPrototype < Object
      def initialize
        function :hasOwnProperty
        function :toString
      end

      def hasOwnProperty(key)
        key?(key.to_sym)
      end

      def toString
        case self
        when undefined
          "[object Undefined]"
        when nil
          "[object Null]"
        when String
          "[object String]"
        when TrueClass, FalseClass
          "[object Boolean]"
        when Numeric
          "[object Number]"
        else
          "[object #{self.js_class}]"
        end
      end
    end

    OBJECT_PROTOTYPE = ObjectPrototype.new

    class LiteralObject < Object
      thunk_method :prototype, OBJECT_PROTOTYPE
      thunk_method :js_class, "Object"
      thunk_method :extensible, true
    end

    class PromotedPrimitive < Object
      attr_accessor :primitive_value
    end
  end
end
