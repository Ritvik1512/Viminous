require "viminous/compilers/eval_compiler"
require "viminous/runtime/object"

module viminous
  class Environment
    def initialize
      @window = viminous::Runtime::Window.new
      @window[:eval] = method(:eval)
      @window[:window] = @window
      @window[:Object] = viminous::Runtime::Function.for_block {}

      # TODO: Have a better way of setting up the initial global scope
      @window[:Object][:prototype] = viminous::Runtime::OBJECT_PROTOTYPE.dup
    end

    # this eval is called from inside JS
    def eval(string)
      parser = RKelly::Parser.new
      ast    = parser.parse(string)

      cm = viminous::Compilers::EvalCompiler.new.compile(ast)
      cm.scope = Rubinius::StaticScope.new(viminous::Runtime)
      cm.scope.const_set :JS_WINDOW, @window
      cm.name  = :__script__
      cm.file  = :"(javascript)"

      binding = Binding.setup(Rubinius::VariableScope.of_sender,
                              Rubinius::CompiledMethod.of_sender,
                              cm.scope,
                              self)

      script = Rubinius::CompiledMethod::Script.new(cm, "(javascript)", true)
      script.eval_source = string
      cm.scope.script = script

      be = Rubinius::BlockEnvironment.new
      be.under_context binding.variables, cm
      be.from_eval!
      be.set_eval_binding binding
      be.call_on_instance(self)
    end

    def evaluate(string)
      parser = RKelly::Parser.new
      ast    = parser.parse(string)

      unless ast
        # TODO: RKelly should provide more useful errors here
        raise "The string #{string} was not valid JavaScript"
      end

      cm = viminous::Compilers::EvalCompiler.new.compile(ast)
      cm.scope = Rubinius::StaticScope.new(viminous::Runtime)
      cm.scope.const_set :JS_WINDOW, @window
      cm.name  = :__script__
      cm.file  = :"(javascript)"

      #puts cm.decode

      script = Rubinius::CompiledMethod::Script.new(cm)
      cm.scope.script = script

      sc = Rubinius::Type.object_singleton_class(self)
      sc.method_table.store :__script__, cm, :public
      Rubinius::VM.reset_method_cache :__script__

      __script__
    end
  end
end
