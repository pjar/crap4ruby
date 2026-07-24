class DefinersCase
  define_method(:double) do |x|
    if x > 0
      x * 2
    else
      -x
    end
  end

  %i[alpha beta].each do |n|
    define_method(n) do
      n.to_s
    end
  end

  # simplecov:disable
  def disabled_method
    "off the record"
  end
  # simplecov:enable

  # :nocov:
  def nocov_method
    "classic marker"
  end
  # :nocov:
end
