class Definers
  # cc: 2 id: Definers#doubled
  define_method(:doubled) do |x|
    x.positive? ? x * 2 : 0
  end

  # cc: 1 id: Definers#stringly
  define_method("stringly") do
    :named_by_string
  end

  %i[alpha beta].each do |n|
    # cc: 2 id: Definers#define_method@14
    define_method(n) do
      n.to_s.sub("a", "A") || raise
    end
  end

  # cc: 1 id: Definers#terse
  define_method(:terse) { :ok }

  # cc: 2 id: Definers.singleton_defined
  define_singleton_method(:singleton_defined) do |x|
    x ? :yes : :no
  end

  # cc: 1 id: Definers#from_lambda
  define_method(:from_lambda, -> { :static })

  # no-row
  attr_accessor :cache

  # no-row
  class_eval "def evaled; 1; end"
end

class Q
  class << self
    # cc: 1 id: Q.from_singleton
    define_method(:from_singleton) { :s }

    [1].each do
      # Transparent blocks push no scope entry: singleton context holds.
      # cc: 1 id: Q.from_block
      define_method(:from_block) { :b }
    end

    # A def switches the counting context but pushes no identity scope,
    # so lexically this is still class << self: the separator stays a dot
    # (contrast fixture 10, where define_method inside def self.install
    # reports with #).
    # cc: 1 id: Q.install
    def install
      # cc: 1 id: Q.added
      define_method(:added) { :a }
    end

    class Inner
      # A nested class scope resets to instance context.
      # cc: 1 id: Q::Inner#from_inner
      define_method(:from_inner) { :i }
    end
  end
end

obj = Object.new
class << obj
  # cc: 1 id: (singleton@67).from_expr
  define_method(:from_expr) { :e }
end
