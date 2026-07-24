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

  # no-row
  attr_accessor :cache

  # no-row
  class_eval "def evaled; 1; end"
end
