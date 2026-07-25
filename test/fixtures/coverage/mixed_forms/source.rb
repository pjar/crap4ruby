class ProbeMisc
  def self.klass_method
    :k
  end

  define_singleton_method(:sing_dyn) do
    :sd
  end

  def defaults(a = 1,
               b = a > 0 ? :p : :n)
    [a, b]
  end

  def outer_with_nested(flag)
    def nested_helper
      :inner
    end
    flag ? nested_helper : nil
  end

  def one_a = 1; def one_b = 2
end
