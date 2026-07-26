module Crap4Ruby
  # One scored method (spec §1, §7.1). `cov` arrives as a Rational and
  # `crap` stays Rational: the gate compares unrounded values and the
  # report rounds half-up (§8), so no binary float error is introduced.
  Row = Struct.new(:method, :units, :hits, :cov, keyword_init: true) do
    def crap
      comp = method.comp
      comp**2 * (1 - cov)**3 + comp
    end
  end
end
