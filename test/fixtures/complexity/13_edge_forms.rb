# Edge forms pinned by CRA-28: spec §5/§6 rules that previously had no
# fixture coverage. Each cc/id is the spec-mandated value, probed against
# the extractor before annotation.
class Guards
  # cc: 2 id: Guards#flip
  def flip(x)
    if (x == 1)..(x == 9)
      :in
    end
  end

  # cc: 1 id: Guards#has_const
  def has_const
    defined?(Foo)
  end

  # cc: 4 id: Guards#pick
  def pick(x)
    case x
    when 1, 2, *SPECIALS then :small
    else :big
    end
  end

  # cc: 2 id: Guards#ratio
  def ratio(a, b) = a > b ?
      a :
      b

  # Assignment fusion keeps the &. flag on the or-write node: the ||= row
  # and the &. row both match (CRA-8 decision B, implemented by CRA-42).
  # cc: 3 id: Guards#toggle_default
  def toggle_default(a)
    a&.b ||= 1
  end
end

class Calc
  # cc: 1 id: Calc#[]
  def [](i)
    i
  end

  # cc: 2 id: Calc#+
  def +(other)
    other ? self : other
  end
end

class Factory
  # cc: 3 id: Factory#build
  def build(flag)
    klass = Class.new do
      # cc: 2 id: Factory::(anon@53)#speak
      def speak(loud)
        loud ? "Y" : "y"
      end
      flag ? :with : :without
    end
    klass
  end
end

class Wiring
  # cc: 2 id: Wiring#install
  def install(blk)
    # no-row
    define_method(:from_pass, &blk)
    :ok
  end

  # cc: 1 id: Wiring#install_proc
  def install_proc(prc)
    # no-row
    define_method(:from_var, prc)
    :ok
  end

  # cc: 2 id: Wiring#from_lambda_later
  define_method(:from_lambda_later,
    ->(x) { x ? 1 : 2 })
end

class Registry
  %i[alpha beta].each do |name|
    # cc: 1 id: Registry.define_singleton_method@87
    define_singleton_method("reset_#{name}") do
      :done
    end
  end
end

helper = Object.new
class << helper
  # cc: 1 id: (singleton@94).from_expr_singleton
  def from_expr_singleton
    :s
  end
end

class Receivers
  # The def-receiver expression evaluates when the def statement runs:
  # its &. counts in the enclosing method (§6); line/branch ownership
  # stays span-based (§7.0).
  # cc: 2 id: Receivers#outer
  def outer(target)
    # cc: 1 id: Receivers::(singleton@108).name
    def (target&.thing).name
    end
  end

  # Defaults execute at invocation time: the ternary counts in the
  # method's own scope, not the class body.
  # cc: 2 id: Receivers#defaulted
  def defaulted(x = (@flag ? 1 : 2))
    x
  end
end
